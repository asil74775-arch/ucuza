import json

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import optional_user
from ..db import SessionLocal, get_db
from ..models import (
    Brand, Category, Compatibility, Experience, ExternalRating, Offer, PriceHistory, Product, RatingHistory, User,
)
from ..services import catalog, matching, pipeline, scoring

router = APIRouter(tags=["catalog"])


def cat_out(c: Category) -> dict:
    return {"id": c.id, "slug": c.slug, "name": c.name, "icon": c.icon, "parent_id": c.parent_id,
            "is_accessory": c.is_accessory, "spec_schema": c.spec_schema}


@router.get("/categories")
async def categories(db: AsyncSession = Depends(get_db)):
    return [cat_out(c) for c in (await db.scalars(select(Category).order_by(Category.id))).all()]


@router.get("/home")
async def home(db: AsyncSession = Depends(get_db), user: User | None = Depends(optional_user)):
    """Ana sayfa: kategoriler halinde ürünler + kişisel öneriler + rozet vitrinleri."""
    cats = (await db.scalars(select(Category).where(Category.parent_id.is_(None), Category.is_accessory.is_(False)))).all()
    sections = []
    for c in cats:
        items = await catalog.search(db, category_id=c.id, user=user, limit=10)
        if items:
            sections.append({"category": cat_out(c), "products": items})
    return {
        "for_you": await catalog.search(db, user=user, limit=10) if user else [],
        "sections": sections,
        "showcases": [
            {"badge": b, "products": await catalog.search(db, badge=b, sort="best", limit=10, personalize=False)}
            for b in ["En İyi Fiyat", "En Güvenilir", "Öğrenciler İçin İdeal", "Kroniksiz"]
        ],
    }


@router.get("/products")
async def products(
    category_id: int | None = None, q: str | None = None,
    sort: str = Query("best", pattern="^(best|cheapest|expensive|fp|rating|popular)$"),
    min_price: float | None = None, max_price: float | None = None,
    specs: str | None = Query(None, description='JSON: {"ram_gb":{"min":16},"panel":["IPS"]}'),
    badge: str | None = None, limit: int = Query(30, le=100), offset: int = 0,
    db: AsyncSession = Depends(get_db), user: User | None = Depends(optional_user),
):
    try:
        filters = json.loads(specs) if specs else None
    except json.JSONDecodeError:
        raise HTTPException(400, "specs JSON geçersiz")
    return await catalog.search(db, category_id=category_id, q=q, sort=sort, min_price=min_price,
                                max_price=max_price, spec_filters=filters, badge=badge, user=user,
                                limit=limit, offset=offset)


@router.get("/categories/{category_id}/facets")
async def facets(category_id: int, db: AsyncSession = Depends(get_db)):
    """Teknik özellik filtreleri için değer aralıkları/seçenekleri."""
    cat = await db.get(Category, category_id)
    if not cat:
        raise HTTPException(404)
    rows = (await db.scalars(select(Product.specs).where(Product.category_id == category_id))).all()
    out = []
    for f in cat.spec_schema or []:
        if not f.get("filterable", True):
            continue
        vals = [r.get(f["key"]) for r in rows if r and r.get(f["key"]) is not None]
        if f["type"] == "number":
            nums = [v for v in vals if isinstance(v, (int, float))]
            if nums:
                out.append({**f, "min": min(nums), "max": max(nums)})
        elif f["type"] == "enum":
            out.append({**f, "options": sorted({str(v) for v in vals})})
        else:
            out.append(f)
    prices = (await db.scalars(select(Product.current_price).where(Product.category_id == category_id))).all()
    return {"specs": out, "price": {"min": min(prices, default=0), "max": max(prices, default=0)}}


@router.get("/products/{pid}")
async def product_detail(pid: int, db: AsyncSession = Depends(get_db)):
    p = await db.get(Product, pid)
    if not p:
        raise HTTPException(404, "Ürün bulunamadı")
    cat = await db.get(Category, p.category_id)
    offers = (await db.scalars(select(Offer).where(Offer.product_id == pid).order_by(Offer.price))).all()
    issues = await catalog.chronic_list(db, pid)
    from ..config import get_settings
    hidden = await db.scalar(select(func.count()).select_from(Experience).where(
        Experience.product_id == pid, Experience.fake_probability >= get_settings().fake_hide_threshold))
    ext = (await db.scalars(select(ExternalRating).where(ExternalRating.product_id == pid)
                            .order_by(ExternalRating.rating_count.desc()))).all()
    exp_count = await db.scalar(select(func.count()).select_from(Experience).where(Experience.product_id == pid))
    return {
        **catalog.card(p), "description": p.description, "model_code": p.model_code, "images": p.images,
        "specs": p.specs, "spec_schema": cat.spec_schema, "category": cat_out(cat), "tags": p.tags,
        "score_breakdown": p.score_breakdown,
        "badge_basis": {b: scoring.BADGE_BASIS.get(b, "") for b in (p.badges or [])},
        "disclaimer": scoring.DISCLAIMER, "durability_score": p.durability_score,
        "fake_review_ratio": p.fake_review_ratio, "fake_reviews_removed": hidden,
        "external_ratings": [{"source": e.source, "rating": e.rating, "rating_count": e.rating_count, "url": e.url,
                              "fetched_at": e.fetched_at.isoformat()} for e in ext],
        "ar_model_url": p.ar_model_url, "tryon_asset_url": p.tryon_asset_url,
        "offers": [{"id": o.id, "seller": o.seller, "price": o.price, "url": o.affiliate_url or o.url,
                    "in_stock": o.in_stock, "source": o.source} for o in offers],
        "chronic_issues": [{"title": i.title, "severity": i.severity, "share": i.share,
                            "mention_count": i.mention_count, "months_active": i.months_active,
                            "is_chronic": i.is_chronic, "timeline": i.timeline} for i in issues if i.is_chronic],
        "frequent_complaints": [{"title": i.title, "share": i.share, "timeline": i.timeline}
                                for i in issues if not i.is_chronic],
        "price_stats": await catalog.price_stats(db, pid),
        "experience_count": exp_count,
    }


@router.get("/products/{pid}/history")
async def history(pid: int, days: int = 365, db: AsyncSession = Depends(get_db)):
    from datetime import datetime, timedelta, timezone
    since = datetime.now(timezone.utc) - timedelta(days=days)
    prices = (await db.scalars(select(PriceHistory).where(PriceHistory.product_id == pid, PriceHistory.recorded_at >= since)
                               .order_by(PriceHistory.recorded_at))).all()
    ratings = (await db.scalars(select(RatingHistory).where(RatingHistory.product_id == pid, RatingHistory.recorded_at >= since)
                                .order_by(RatingHistory.recorded_at))).all()
    return {"prices": [{"t": h.recorded_at.isoformat(), "price": h.price} for h in prices],
            "ratings": [{"t": h.recorded_at.isoformat(), "rating": h.avg_rating, "ai_rating": h.ai_rating,
                         "count": h.count} for h in ratings]}


@router.post("/products/{pid}/refresh")
async def refresh(pid: int, bg: BackgroundTasks):
    """Tekliflerden fiyat/puan güncelleme + kullanıcı yorumlarının AI analizi (arka planda)."""
    async def job():
        async with SessionLocal() as s:
            await pipeline.refresh_product(s, pid)
    bg.add_task(job)
    return {"queued": True}


@router.get("/products/{pid}/alternatives")
async def alternatives(pid: int, db: AsyncSession = Depends(get_db)):
    p = await db.get(Product, pid)
    if not p:
        raise HTTPException(404)
    return await catalog.alternatives(db, p, limit=8)


# ------------------------------------------------------------ Aksesuar uyumluluk platformu
@router.get("/accessories/brands")
async def acc_brands(category_id: int, db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(Brand.id, Brand.name).join(Product, Product.brand_id == Brand.id)
                             .where(Product.category_id == category_id).distinct().order_by(Brand.name))).all()
    return [{"id": i, "name": n} for i, n in rows]


@router.get("/accessories/models")
async def acc_models(category_id: int, brand_id: int, q: str | None = None, db: AsyncSession = Depends(get_db)):
    stmt = select(Product).where(Product.category_id == category_id, Product.brand_id == brand_id)
    if q:
        stmt = stmt.where(Product.name.ilike(f"%{q}%") | Product.model_code.ilike(f"%{q}%"))
    return [{"id": p.id, "name": p.name, "model_code": p.model_code}
            for p in (await db.scalars(stmt.order_by(Product.name))).unique().all()]


@router.get("/accessories/types")
async def acc_types(device_id: int, db: AsyncSession = Depends(get_db)):
    device = await db.get(Product, device_id)
    if not device:
        raise HTTPException(404)
    acc_cats = (await db.scalars(select(Category).where(Category.is_accessory.is_(True)))).all()
    # Yalnızca bu cihaz kategorisine aksesuar sunan kategoriler (tags: "for:<slug>")
    dev_slug = device.category.slug
    return [cat_out(c) for c in acc_cats if f"for:{dev_slug}" in (c.tags or []) or not any(
        t.startswith("for:") for t in c.tags or [])]


@router.get("/accessories/compatible")
async def compatible(device_id: int, accessory_category_id: int, sort: str = "best",
                     db: AsyncSession = Depends(get_db)):
    device = await db.get(Product, device_id)
    if not device:
        raise HTTPException(404)
    accs = (await db.scalars(select(Product).where(Product.category_id == accessory_category_id))).unique().all()
    explicit = {c.accessory_id: c for c in (await db.scalars(
        select(Compatibility).where(Compatibility.device_id == device_id))).all()}
    out = []
    for a in accs:
        level, notes = matching.check_compat(a.specs or {}, device.specs or {})
        if a.id in explicit:
            level, notes = "full", [explicit[a.id].notes or "Üretici/kullanıcı doğrulamalı uyum"]
        if level == "none":
            continue
        out.append({**catalog.card(a), "compat": level, "compat_notes": notes})
    card_sorts = {"best": lambda x: -x["best_choice_score"], "cheapest": lambda x: x["price"],
                  "expensive": lambda x: -x["price"], "fp": lambda x: -x["fp_score"],
                  "rating": lambda x: -(x["ai_rating"] or x["rating"]), "popular": lambda x: -x["rating_count"]}
    key = card_sorts.get(sort, card_sorts["best"])
    out.sort(key=lambda x: (x["compat"] != "full", key(x)))
    return {"device": {"id": device.id, "name": device.name, "specs": device.specs}, "results": out}
