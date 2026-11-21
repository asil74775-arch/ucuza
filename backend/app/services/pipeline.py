"""Ürün analiz boru hattı.

refresh_product:  kaynaklardan teklif + PUAN çek -> analyze_reviews -> rescore_category
analyze_reviews:  UCUZA KULLANICI YORUMLARI üzerinde kural + Gemini ile AI yıldız, duygu,
                  şikayet, sahte olasılığı; kronik tespit; dış puanlarla birleşik ortalama
Dış kaynaklardan yorum metni TOPLANMAZ; yalnızca puan ortalaması ve puan sayısı alınır.
rescore_category: En İyi Seçim / F/P puanı + güven rozetleri
discover:         sistemde olmayan ürünü internetteki lisanslı kaynaklardan bulup ekler
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..models import (
    Brand, Category, ChronicIssue, Experience, ExternalRating, Offer, PriceHistory, Product, RatingHistory,
)
from . import chronic, fake_reviews, scoring
from .gemini import GeminiError, gemini
from .sources import enabled_sources
from .sources.base import FoundProduct

log = logging.getLogger("fiyatradar.pipeline")


# ------------------------------------------------------------------ Puan birleştirme
async def combined_rating(db: AsyncSession, product: Product) -> None:
    """avg_rating = dış platform puanları + FiyatRadar yorum puanları (puan sayısına göre ağırlıklı)."""
    ext = (await db.scalars(select(ExternalRating).where(ExternalRating.product_id == product.id))).all()
    ext_sum = sum(e.rating * e.rating_count for e in ext)
    ext_n = sum(e.rating_count for e in ext)
    own_n = product.review_count
    own_sum = product.ai_rating * own_n
    product.external_rating_count = ext_n
    product.rating_count = ext_n + own_n
    product.avg_rating = round((ext_sum + own_sum) / (ext_n + own_n), 2) if ext_n + own_n else 0


# ------------------------------------------------------------------ Yorum analizi (yalnızca uygulama içi)
async def analyze_reviews(db: AsyncSession, product_id: int) -> dict:
    s = get_settings()
    reviews = (await db.scalars(select(Experience).where(Experience.product_id == product_id))).unique().all()
    product = await db.get(Product, product_id)
    lite = [fake_reviews.ReviewLite(r.id, r.text, float(r.rating), r.created_at, str(r.user_id)) for r in reviews]
    heur = {v.id: v for v in fake_reviews.heuristic_scores(lite)} if lite else {}

    ai: dict[int, dict] = {}
    # KVKK: yalnızca yazarı açık rıza vermiş yorumlar Gemini'ye gönderilir (kimlik bilgisi gönderilmez).
    pending = [r for r in reviews if not r.analyzed and r.user and r.user.ai_consent]
    if gemini.available and pending:
        for i in range(0, len(pending), 25):
            chunk = pending[i:i + 25]
            prompt = "Yorumları analiz et:\n" + "\n".join(
                f"[id={r.id}] (kullanıcı puanı: {r.rating}) {r.text[:800]}" for r in chunk)
            try:
                for row in await gemini.json(prompt, fake_reviews.AI_SCHEMA, system=fake_reviews.AI_SYSTEM):
                    ai[int(row["id"])] = row
            except GeminiError as e:
                log.warning("AI yorum analizi başarısız: %s", e)

    for r in reviews:
        h = heur[r.id]
        a = ai.get(r.id)
        if not r.content_hash:
            r.content_hash = fake_reviews.content_hash(r.text)
        if a:
            r.ai_stars = max(1.0, min(5.0, float(a["stars"])))
            r.sentiment = a["sentiment"]
            r.complaints = a.get("complaints", [])
            extra = [a["fake_reason"]] if a.get("fake_reason") and a["fake_probability"] > 0.4 else []
            r.fake_probability = fake_reviews.combine(h.probability, float(a["fake_probability"]))
            r.fake_reasons = list(h.reasons) + extra
            r.analyzed = True
        else:
            if r.ai_stars is None:  # AI yoksa: kullanıcının verdiği puan + sözlük tabanlı şikayet çıkarımı
                r.ai_stars = float(r.rating)
                r.sentiment = "pos" if r.rating >= 4 else "neg" if r.rating <= 2 else "neu"
                r.complaints = r.complaints or _lexicon_complaints(r.text, r.rating)
            r.fake_probability = max(h.probability, r.fake_probability if r.analyzed else 0)
            r.fake_reasons = h.reasons or r.fake_reasons
        # Sahte yorum: gizlenir. Moderasyonla gizlenmiş yorum sahte değilse bile gizli kalır.
        if r.fake_probability >= s.fake_hide_threshold:
            r.is_hidden = True

    visible = [r for r in reviews if not r.is_hidden]
    product.review_count = len(visible)
    product.ai_rating = round(sum(r.ai_stars or r.rating for r in visible) / len(visible), 2) if visible else 0
    product.fake_review_ratio = round(
        sum(1 for r in reviews if r.fake_probability >= s.fake_hide_threshold) / len(reviews), 3) if reviews else 0
    await combined_rating(db, product)

    # Kronik sorunlar (zamana yayılmış tekrar eden şikayetler)
    mentions = [chronic.ComplaintMention(c["key"], c["label"], r.created_at)
                for r in visible for c in (r.complaints or [])]
    issues = chronic.detect(mentions, len(visible), s.chronic_min_share, s.chronic_min_months)
    await db.execute(delete(ChronicIssue).where(ChronicIssue.product_id == product_id))
    for it in issues:
        db.add(ChronicIssue(product_id=product_id, key=it.key, title=it.title, mention_count=it.mention_count,
                            share=it.share, months_active=it.months_active, severity=it.severity,
                            is_chronic=it.is_chronic, first_seen=it.first_seen, last_seen=it.last_seen,
                            timeline=it.timeline))
    product.is_chronic_free = chronic.is_chronic_free(issues, len(visible), s.chronic_free_min_reviews)
    high = sum(1 for i in issues if i.is_chronic and i.severity == "high")
    product.durability_score = round(max(0.1, 1 - 0.2 * high - 0.07 * sum(1 for i in issues if i.is_chronic)), 2)

    db.add(RatingHistory(product_id=product_id, avg_rating=product.avg_rating,
                         ai_rating=product.ai_rating, count=product.rating_count))
    await db.commit()
    return {"total": len(reviews), "hidden": len(reviews) - len(visible), "issues": len(issues)}


_NEG = ["bozuk", "kötü", "pişman", "iade", "arıza", "berbat", "yavaş", "kırıldı", "ısınıyor", "çabuk bitiyor"]
_COMPLAINT_LEXICON = {
    "overheating": ("ısın", "Aşırı ısınma"),
    "battery_drain": ("pil", "Pil/batarya çabuk bitiyor"),
    "hinge_break": ("menteşe", "Menteşe kırılması"),
    "screen_issue": ("ekran", "Ekran sorunu"),
    "noise": ("ses yap", "Fan/ses gürültüsü"),
    "connectivity": ("bağlantı kop", "Bağlantı kopması"),
}


def _lexicon_complaints(text: str, rating: float) -> list[dict]:
    t = text.lower()
    if rating >= 4 and not any(w in t for w in _NEG):
        return []
    return [{"key": k, "label": lbl} for k, (needle, lbl) in _COMPLAINT_LEXICON.items() if needle in t]


# ------------------------------------------------------------------ Puanlama
async def rescore_category(db: AsyncSession, category_id: int) -> int:
    cat = await db.get(Category, category_id)
    products = (await db.scalars(select(Product).where(Product.category_id == category_id))).all()
    if not products:
        return 0
    chronic_rows = (await db.execute(
        select(ChronicIssue.product_id, ChronicIssue.severity)
        .where(ChronicIssue.product_id.in_([p.id for p in products]), ChronicIssue.is_chronic.is_(True))
    )).all()
    high, total = {}, {}
    for pid, sev in chronic_rows:
        total[pid] = total.get(pid, 0) + 1
        if sev == "high":
            high[pid] = high.get(pid, 0) + 1
    inputs = [scoring.ScoreInput(
        id=p.id, price=p.current_price, rating=p.avg_rating or p.ai_rating or 3.5, rating_count=p.rating_count,
        specs=p.specs or {}, durability=p.durability_score, chronic_high=high.get(p.id, 0),
        chronic_total=total.get(p.id, 0), fake_ratio=p.fake_review_ratio, is_chronic_free=p.is_chronic_free,
    ) for p in products]
    results = {r.id: r for r in scoring.score_category(inputs, cat.spec_schema or [])}
    max_count = max(p.rating_count for p in products) or 1
    for p in products:
        r = results[p.id]
        p.best_choice_score, p.fp_score, p.score_breakdown, p.badges = r.best_choice, r.fp, r.breakdown, r.badges
        p.popularity = round(p.rating_count / max_count, 3)
    await db.commit()
    return len(products)


# ------------------------------------------------------------------ Fiyat
async def record_price(db: AsyncSession, product: Product, offers: list[Offer] | None = None) -> None:
    if offers is None:
        offers = (await db.scalars(select(Offer).where(Offer.product_id == product.id, Offer.in_stock.is_(True)))).all()
    if offers:
        product.current_price = min(o.price for o in offers)
    db.add(PriceHistory(product_id=product.id, price=product.current_price))


# ------------------------------------------------------------------ Keşif / içe aktarma
CATEGORY_GUESS_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "category_slug": {"type": "STRING"},
        "brand": {"type": "STRING"},
        "model_code": {"type": "STRING"},
        "specs": {"type": "OBJECT", "properties": {}, "nullable": True},
        "tags": {"type": "ARRAY", "items": {"type": "STRING"}},
    },
    "required": ["category_slug", "brand"],
}


async def _guess_category(db: AsyncSession, fp: FoundProduct) -> tuple[Category, dict]:
    cats = (await db.scalars(select(Category))).all()
    by_slug = {c.slug: c for c in cats}
    if fp.category_hint and fp.category_hint in by_slug:
        return by_slug[fp.category_hint], {}
    if gemini.available:
        try:
            g = await gemini.json(
                f"Ürün: {fp.name}\nAçıklama: {fp.description[:500]}\nKategoriler: {list(by_slug)}\n"
                "Bu ürün hangi kategoride, markası ve model kodu ne? Kategori şemasındaki teknik özellikleri "
                "biliyorsan specs içinde ver. Zevk etiketlerini (budget, premium, gaming, cosmetics, tech, home, "
                "fashion, sports) seç.", CATEGORY_GUESS_SCHEMA)
            if g["category_slug"] in by_slug:
                return by_slug[g["category_slug"]], g
        except GeminiError:
            pass
    name = fp.name.lower()
    for c in cats:
        if c.name.lower().split()[0] in name or c.slug in name:
            return c, {}
    return by_slug.get("diger") or cats[0], {}


async def upsert_found(db: AsyncSession, fp: FoundProduct) -> Product:
    existing = None
    for p in (await db.scalars(select(Product).where(Product.name.ilike(f"%{fp.name[:40]}%")).limit(5))).all():
        if (p.external_ids or {}).get(fp.source) == fp.external_id or p.name.lower() == fp.name.lower():
            existing = p
            break
    if existing is None:
        cat, extra = await _guess_category(db, fp)
        brand_name = fp.brand or extra.get("brand") or fp.name.split()[0]
        brand = await db.scalar(select(Brand).where(func.lower(Brand.name) == brand_name.lower()))
        if not brand:
            brand = Brand(name=brand_name)
            db.add(brand)
            await db.flush()
        existing = Product(
            category_id=cat.id, brand_id=brand.id, name=fp.name, model_code=extra.get("model_code"),
            description=fp.description, specs={**(extra.get("specs") or {}), **fp.specs}, images=fp.images,
            tags=extra.get("tags") or list(cat.tags or []), current_price=fp.price or 0,
            external_ids={fp.source: fp.external_id}, source=fp.source,
        )
        db.add(existing)
        await db.flush()
    else:
        existing.external_ids = {**(existing.external_ids or {}), fp.source: fp.external_id}
    if fp.price:
        offer = await db.scalar(select(Offer).where(Offer.product_id == existing.id, Offer.source == fp.source,
                                                    Offer.url == fp.url))
        if offer:
            offer.price, offer.fetched_at = fp.price, datetime.now(timezone.utc)
        else:
            db.add(Offer(product_id=existing.id, source=fp.source, seller=fp.seller or fp.source, price=fp.price,
                         url=fp.url, affiliate_url=fp.affiliate_url))
        await db.flush()
        await record_price(db, existing)
    if fp.rating and fp.rating_count:
        await save_external_rating(db, existing, fp.rating_source or fp.source, fp.rating, fp.rating_count, fp.url)
    await db.commit()
    return existing


async def save_external_rating(db: AsyncSession, product: Product, source: str, rating: float, count: int,
                               url: str | None = None) -> None:
    row = await db.scalar(select(ExternalRating).where(ExternalRating.product_id == product.id,
                                                       ExternalRating.source == source))
    if row:
        row.rating, row.rating_count, row.url = float(rating), int(count), url
    else:
        db.add(ExternalRating(product_id=product.id, source=source, rating=float(rating),
                              rating_count=int(count), url=url))
    await db.flush()
    await combined_rating(db, product)


async def refresh_product(db: AsyncSession, product_id: int) -> dict:
    product = await db.get(Product, product_id)
    brand = product.brand.name if product.brand else ""
    for src in enabled_sources():
        try:
            for fp in await src.search(f"{brand} {product.model_code or product.name}", limit=3):
                fp.name = product.name  # aynı ürüne teklif olarak bağla
                await upsert_found(db, fp)
        except Exception as e:  # noqa: BLE001
            log.warning("%s teklif alınamadı: %s", src.name, e)
    stats = await analyze_reviews(db, product_id)
    await rescore_category(db, product.category_id)
    return stats


async def discover(db: AsyncSession, query: str, limit: int = 5) -> list[Product]:
    """Sistemde olmayan ürünleri lisanslı kaynaklarda arar; ürün, fiyat ve puanını ekler."""
    created: list[Product] = []
    for src in enabled_sources():
        try:
            for fp in await src.search(query, limit=limit):
                created.append(await upsert_found(db, fp))
        except Exception as e:  # noqa: BLE001
            log.warning("%s keşif hatası: %s", src.name, e)
    seen, uniq = set(), []
    for p in created:
        if p.id not in seen:
            seen.add(p.id)
            uniq.append(p)
    for p in uniq[:limit]:
        await analyze_reviews(db, p.id)
    for cid in {p.category_id for p in uniq}:
        await rescore_category(db, cid)
    return uniq[:limit]
