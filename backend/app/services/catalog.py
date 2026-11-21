"""Katalog sorguları ve ürün düzeyi akıllı analizler."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import ChronicIssue, Category, PriceHistory, Product, TasteProfile, User
from . import matching, scoring

SORTS = {
    "best": lambda p: -p.best_choice_score,
    "cheapest": lambda p: p.current_price,
    "expensive": lambda p: -p.current_price,
    "fp": lambda p: -p.fp_score,
    "rating": lambda p: -(p.avg_rating or p.ai_rating),
    "popular": lambda p: -p.rating_count,
}


def card(p: Product, personal_score: float | None = None) -> dict:
    return {
        "id": p.id, "name": p.name, "brand": p.brand.name if p.brand else None,
        "category_id": p.category_id, "image": (p.images or [None])[0], "price": p.current_price,
        "currency": p.currency, "rating": p.avg_rating, "ai_rating": p.ai_rating, "rating_count": p.rating_count,
        "review_count": p.review_count,
        "best_choice_score": p.best_choice_score, "fp_score": p.fp_score, "badges": p.badges or [],
        "is_chronic_free": p.is_chronic_free, "personal_score": personal_score,
        "ar_type": p.ar_type,
    }


def spec_match(specs: dict, filters: dict) -> bool:
    """filters: {"ram_gb": {"min": 16, "max": 64}, "panel": "IPS" | ["IPS","OLED"], "nfc": true}"""
    for k, cond in filters.items():
        v = specs.get(k)
        if isinstance(cond, dict):
            if not isinstance(v, (int, float)):
                return False
            if "min" in cond and v < cond["min"]:
                return False
            if "max" in cond and v > cond["max"]:
                return False
        elif isinstance(cond, list):
            if str(v).lower() not in [str(c).lower() for c in cond]:
                return False
        elif isinstance(cond, bool):
            if bool(v) != cond:
                return False
        elif str(v).lower() != str(cond).lower():
            return False
    return True


async def taste_of(db: AsyncSession, user: User | None) -> dict:
    if not user:
        return {}
    t = await db.get(TasteProfile, user.id)
    return t.weights if t else {}


async def search(
    db: AsyncSession, *, category_id: int | None = None, q: str | None = None, sort: str = "best",
    min_price: float | None = None, max_price: float | None = None, spec_filters: dict | None = None,
    badge: str | None = None, user: User | None = None, limit: int = 30, offset: int = 0,
    personalize: bool = True, exclude_ids: list[int] | None = None,
) -> list[dict]:
    stmt = select(Product)
    if category_id:
        sub = select(Category.id).where(or_(Category.id == category_id, Category.parent_id == category_id))
        stmt = stmt.where(Product.category_id.in_(sub))
    if q:
        for term in q.split():
            like = f"%{term}%"
            stmt = stmt.where(or_(Product.name.ilike(like), Product.model_code.ilike(like),
                                  Product.description.ilike(like)))
    if min_price is not None:
        stmt = stmt.where(Product.current_price >= min_price)
    if max_price is not None:
        stmt = stmt.where(Product.current_price <= max_price)
    if exclude_ids:
        stmt = stmt.where(Product.id.not_in(exclude_ids))
    rows = (await db.scalars(stmt.limit(2000))).unique().all()
    if spec_filters:
        rows = [p for p in rows if spec_match(p.specs or {}, spec_filters)]
    if badge:
        rows = [p for p in rows if badge in (p.badges or [])]

    weights = await taste_of(db, user) if personalize else {}
    if weights and sort == "best":
        by_cat: dict[int, list[float]] = {}
        for p in rows:
            by_cat.setdefault(p.category_id, []).append(p.current_price)
        scored = [(p, matching.personalize(p.best_choice_score, p.tags or [],
                                           matching.price_tier(p.current_price, by_cat[p.category_id]), weights))
                  for p in rows]
        scored.sort(key=lambda x: -x[1])
        return [card(p, s) for p, s in scored[offset:offset + limit]]
    rows = sorted(rows, key=SORTS.get(sort, SORTS["best"]))
    return [card(p) for p in rows[offset:offset + limit]]


# ------------------------------------------------------------------ Fiyat istatistiği
async def price_stats(db: AsyncSession, product_id: int, days: int = 90) -> dict:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    hist = (await db.scalars(select(PriceHistory).where(
        PriceHistory.product_id == product_id, PriceHistory.recorded_at >= since)
        .order_by(PriceHistory.recorded_at))).all()
    prices = [h.price for h in hist]
    if not prices:
        return {"min": None, "avg": None, "max": None, "trend": "unknown", "points": 0}
    third = max(1, len(prices) // 3)
    early, late = sum(prices[:third]) / third, sum(prices[-third:]) / third
    trend = "down" if late < early * 0.97 else "up" if late > early * 1.03 else "flat"
    return {"min": min(prices), "avg": round(sum(prices) / len(prices), 2), "max": max(prices),
            "trend": trend, "points": len(prices)}


# ------------------------------------------------------------------ Alternatif bulucu
async def alternatives(db: AsyncSession, product: Product, limit: int = 5, min_saving: float = 0.10) -> list[dict]:
    cat = await db.get(Category, product.category_id)
    peers = (await db.scalars(select(Product).where(Product.category_id == product.category_id,
                                                    Product.id != product.id))).unique().all()
    schema = cat.spec_schema or []
    items = [scoring.ScoreInput(p.id, p.current_price, 0, 0, p.specs or {}, 0) for p in peers + [product]]
    ranges = scoring.spec_ranges(items, schema)
    base = matching.spec_vector(product.specs or {}, schema, ranges)
    out = []
    for p in peers:
        if not p.current_price or p.current_price > product.current_price * (1 - min_saving):
            continue
        if "Yüksek Riskli" in (p.badges or []):
            continue
        sim = matching.cosine(base, matching.spec_vector(p.specs or {}, schema, ranges))
        if sim < 0.70:
            continue
        saving = product.current_price - p.current_price
        out.append({**card(p), "similarity": round(sim * 100, 1), "saving": round(saving, 2),
                    "saving_pct": round(saving / product.current_price * 100, 1),
                    "differences": spec_diff(product.specs or {}, p.specs or {}, schema)})
    out.sort(key=lambda x: (-(x["similarity"] * 0.6 + x["best_choice_score"] * 0.4)))
    return out[:limit]


def spec_diff(a: dict, b: dict, schema: list[dict]) -> list[str]:
    diffs = []
    for f in schema:
        va, vb = a.get(f["key"]), b.get(f["key"])
        if va != vb and va is not None and vb is not None:
            diffs.append(f"{f['label']}: {va}{f.get('unit','')} → {vb}{f.get('unit','')}")
    return diffs[:6]


# ------------------------------------------------------------------ Karşılaştırma düellosu
async def duel(db: AsyncSession, a: Product, b: Product) -> dict:
    cat = await db.get(Category, a.category_id)
    schema = cat.spec_schema or []
    rounds = []

    def add(label, va, vb, higher_better, unit=""):
        if va is None or vb is None:
            return
        if va == vb:
            winner = "tie"
        else:
            winner = "a" if (va > vb) == higher_better else "b"
        rounds.append({"label": label, "a": va, "b": vb, "unit": unit, "winner": winner})

    add("Fiyat", a.current_price, b.current_price, False, " TL")
    add("Genel Puan", a.avg_rating, b.avg_rating, True, "/5")
    add("BinÖlçBirAl Kullanıcı Puanı (AI)", a.ai_rating, b.ai_rating, True, "/5")
    add("Fiyat/Performans", a.fp_score, b.fp_score, True)
    add("Dayanıklılık", a.durability_score, b.durability_score, True)
    add("En İyi Seçim Puanı", a.best_choice_score, b.best_choice_score, True)
    add("Sahte Yorum Oranı", a.fake_review_ratio, b.fake_review_ratio, False)
    if b.category_id == a.category_id:
        for f in schema:
            va, vb = (a.specs or {}).get(f["key"]), (b.specs or {}).get(f["key"])
            if f.get("type") == "number" and f.get("higher_is_better") is not None:
                add(f["label"], va, vb, f["higher_is_better"], f.get("unit", ""))
            elif f.get("type") == "bool" and f.get("higher_is_better") is not None and va is not None and vb is not None:
                add(f["label"], int(bool(va)), int(bool(vb)), bool(f["higher_is_better"]))
    a_w = sum(1 for r in rounds if r["winner"] == "a")
    b_w = sum(1 for r in rounds if r["winner"] == "b")
    overall = "a" if a_w > b_w else "b" if b_w > a_w else (
        "a" if a.best_choice_score >= b.best_choice_score else "b")
    return {"a": card(a), "b": card(b), "rounds": rounds, "score": {"a": a_w, "b": b_w}, "overall_winner": overall}


# ------------------------------------------------------------------ Satın almalı mıyım (kural katmanı)
async def chronic_list(db: AsyncSession, product_id: int) -> list[ChronicIssue]:
    return (await db.scalars(select(ChronicIssue).where(ChronicIssue.product_id == product_id)
                             .order_by(ChronicIssue.is_chronic.desc(), ChronicIssue.share.desc()))).all()


async def buy_signals(db: AsyncSession, product: Product, budget: float | None) -> dict:
    stats = await price_stats(db, product.id)
    issues = await chronic_list(db, product.id)
    alts = await alternatives(db, product, limit=3)
    signals, verdict = [], "AL"
    if budget and product.current_price > budget:
        signals.append(f"Fiyat ({product.current_price:.0f} TL) bütçenizi ({budget:.0f} TL) aşıyor")
        verdict = "ALMA"
    if any(i.is_chronic and i.severity == "high" for i in issues):
        signals.append("Ciddi kronik sorun tespit edildi")
        verdict = "ALMA"
    if "Yüksek Riskli" in (product.badges or []):
        signals.append("Ürün Yüksek Riskli olarak işaretli")
        verdict = "ALMA"
    if verdict == "AL" and stats["avg"] and product.current_price > stats["avg"] * 1.08:
        signals.append(f"Güncel fiyat 90 günlük ortalamanın (%.0f TL) belirgin üzerinde" % stats["avg"])
        verdict = "BEKLE"
    if verdict == "AL" and stats["trend"] == "down":
        signals.append("Fiyat düşüş eğiliminde, birkaç gün beklemek kazandırabilir")
        verdict = "BEKLE"
    if verdict == "AL" and alts and alts[0]["saving_pct"] >= 20 and alts[0]["similarity"] >= 85:
        signals.append(f"Çok benzer ve %{alts[0]['saving_pct']:.0f} daha ucuz alternatif var: {alts[0]['name']}")
        verdict = "BEKLE"
    if verdict == "AL":
        signals.append("Fiyat makul, kronik sorun yok, puanlar güvenilir")
    return {"verdict": verdict, "signals": signals, "price_stats": stats,
            "chronic": [{"title": i.title, "severity": i.severity, "is_chronic": i.is_chronic} for i in issues],
            "alternatives": alts}
