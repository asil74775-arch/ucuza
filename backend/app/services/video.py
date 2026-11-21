"""Video ile ürün keşfi ve "almaya değer mi" analizi.

Akış: yükle -> Gemini videodaki ürünü tespit eder -> katalogda eşleştir ->
yoksa lisanslı kaynaklardan bul & ekle -> yorumları/sahte yorumları/fiyat
geçmişini/alternatifleri kontrol et -> karar.
"""
from __future__ import annotations

import logging
from pathlib import Path

from sqlalchemy import func, or_, select

from ..db import SessionLocal
from ..models import Brand, Experience, Product, User, VideoJob
from . import assistant, catalog, pipeline
from .gemini import GeminiError, gemini

log = logging.getLogger("ucuza.video")

DETECT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "found": {"type": "BOOLEAN"},
        "brand": {"type": "STRING"},
        "model": {"type": "STRING"},
        "full_name": {"type": "STRING"},
        "category_hint": {"type": "STRING"},
        "confidence": {"type": "NUMBER"},
        "seen_at_seconds": {"type": "NUMBER"},
        "visible_features": {"type": "ARRAY", "items": {"type": "STRING"}},
        "claims_in_video": {"type": "ARRAY", "items": {"type": "STRING"},
                            "description": "Videoda ürün hakkında yapılan iddialar"},
        "is_sponsored_content": {"type": "BOOLEAN"},
    },
    "required": ["found", "confidence"],
}


async def _match(db, brand: str | None, model: str | None, full: str | None) -> Product | None:
    terms = [t for t in [model, full] if t]
    for t in terms:
        stmt = select(Product).where(or_(Product.model_code.ilike(f"%{t}%"), Product.name.ilike(f"%{t}%")))
        if brand:
            stmt = stmt.join(Brand, isouter=True).where(func.lower(Brand.name) == brand.lower())
        p = (await db.scalars(stmt.limit(1))).unique().first()
        if p:
            return p
    return None


async def process(job_id: int) -> None:
    async with SessionLocal() as db:
        job = await db.get(VideoJob, job_id)
        user = await db.get(User, job.user_id)
        try:
            job.status, job.stage = "processing", "Videodaki ürün tespit ediliyor"
            await db.commit()
            if not gemini.available:
                raise GeminiError("Video analizi şu anda kullanılamıyor")
            det = await gemini.json(
                "Bu videodaki ana ürünü tespit et (marka, tam model). Ekranda/ambalajda yazan model kodlarını "
                "oku. Videonun sponsorlu içerik olup olmadığını ve ürün hakkında yapılan iddiaları çıkar.",
                DETECT_SCHEMA, extra_parts=[await gemini.media_part(job.file_path)])
            if not det.get("found") or det.get("confidence", 0) < 0.35:
                job.status, job.result = "done", {"detected": det, "message": "Videoda net bir ürün tespit edilemedi."}
                await db.commit()
                return
            job.stage = "Katalogda aranıyor"
            await db.commit()
            product = await _match(db, det.get("brand"), det.get("model"), det.get("full_name"))
            added = False
            if not product:
                job.stage = "Ürün sistemde yok, internette aranıp ekleniyor"
                await db.commit()
                q = det.get("full_name") or f"{det.get('brand','')} {det.get('model','')}"
                found = await pipeline.discover(db, q.strip(), limit=1)
                product, added = (found[0] if found else None), bool(found)
            if not product:
                job.status, job.result = "done", {"detected": det, "message": "Ürün tespit edildi ama hiçbir kaynakta bulunamadı."}
                await db.commit()
                return
            job.product_id = product.id
            job.stage = "Puanlar, kullanıcı yorumları ve fiyat geçmişi inceleniyor"
            await db.commit()
            await pipeline.refresh_product(db, product.id)
            await db.refresh(product)
            hidden = await db.scalar(select(func.count()).select_from(Experience).where(
                Experience.product_id == product.id, Experience.fake_probability >= 0.7))
            verdict = await assistant.should_buy(db, user, product, None,
                                                 "Videoda gördüğüm ürün almaya değer mi?")
            job.status, job.stage = "done", "Tamamlandı"
            job.result = {
                "detected": det, "product": catalog.card(product), "added_to_catalog": added,
                "fake_reviews_removed": hidden, "verdict": verdict,
                "price_stats": verdict["signals"]["price_stats"], "alternatives": verdict["signals"]["alternatives"],
                "warning": "Bu video sponsorlu içerik olabilir; iddialara temkinli yaklaşın."
                if det.get("is_sponsored_content") else None,
            }
            await db.commit()
        except Exception as e:  # noqa: BLE001
            log.exception("video job %s başarısız", job_id)
            job.status, job.error = "failed", str(e)[:500]
            await db.commit()
        finally:
            # Veri minimizasyonu: video analiz biter bitmez sunucudan silinir.
            Path(job.file_path).unlink(missing_ok=True)
