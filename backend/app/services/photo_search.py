"""Fotoğraf ile ürün arama.

Akış: fotoğraf -> Gemini Vision ürünü tanır -> katalogda ara -> bulamazsa
affiliate feed'den keşfet -> ürün kartı + "almaya değer mi" sinyalleri döner.
Video analizinden farklı olarak senkrondur (job kuyruğu yok) ve fotoğraf
analiz biter bitmez sunucudan silinir.
"""
from __future__ import annotations

import base64
import logging
from pathlib import Path

from sqlalchemy import func, or_, select

from ..models import Brand, Experience, Product
from . import assistant, catalog, pipeline
from .gemini import GeminiError, gemini

log = logging.getLogger("fiyatradar.photo_search")

DETECT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "found": {"type": "BOOLEAN"},
        "brand": {"type": "STRING"},
        "model": {"type": "STRING"},
        "full_name": {"type": "STRING"},
        "category_hint": {"type": "STRING"},
        "confidence": {"type": "NUMBER"},
        "visible_features": {"type": "ARRAY", "items": {"type": "STRING"}},
        "barcode_text": {"type": "STRING", "description": "Fotoğrafta görünen barkod/QR metin varsa"},
        "label_text": {"type": "STRING", "description": "Ambalaj veya etikette okunan model/seri kodu"},
    },
    "required": ["found", "confidence"],
}


async def _match(db, brand: str | None, model: str | None, full: str | None) -> Product | None:
    terms = [t for t in [model, full, brand] if t]
    for t in terms:
        stmt = select(Product).where(
            or_(Product.model_code.ilike(f"%{t}%"), Product.name.ilike(f"%{t}%"))
        )
        if brand and t != brand:
            stmt = stmt.join(Brand, isouter=True).where(func.lower(Brand.name) == brand.lower())
        p = (await db.scalars(stmt.limit(1))).unique().first()
        if p:
            return p
    return None


async def search(db, user, file_path: str) -> dict:
    """Fotoğrafı analiz et, ürün bul/ekle, verdict döndür."""
    try:
        if not gemini.available:
            raise GeminiError("Fotoğraf arama şu anda kullanılamıyor")

        raw = Path(file_path).read_bytes()
        b64 = base64.b64encode(raw).decode()
        # content_type tahmini (jpg/png/webp hepsi çalışır)
        suffix = Path(file_path).suffix.lower()
        mime = {"jpg": "image/jpeg", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                ".png": "image/png", ".webp": "image/webp"}.get(suffix, "image/jpeg")

        image_part = {"inline_data": {"mime_type": mime, "data": b64}}

        det = await gemini.json(
            "Bu fotoğraftaki ürünü tanımla: marka, tam model adı ve kodu. "
            "Ambalaj, etiket, barkod veya ekranda yazan metni oku. "
            "Ürün yoksa veya emin değilsen found=false döndür.",
            DETECT_SCHEMA,
            extra_parts=[image_part],
        )

        if not det.get("found") or det.get("confidence", 0) < 0.30:
            return {
                "detected": det,
                "product": None,
                "message": "Fotoğrafta net bir ürün tespit edilemedi. Daha iyi ışıkta veya daha yakından çekin.",
            }

        product = await _match(db, det.get("brand"), det.get("model"), det.get("full_name"))
        added = False
        if not product:
            q = det.get("full_name") or f"{det.get('brand', '')} {det.get('model', '')}".strip()
            if q:
                found = await pipeline.discover(db, q, limit=1)
                product, added = (found[0] if found else None), bool(found)

        if not product:
            return {
                "detected": det,
                "product": None,
                "message": f"'{det.get('full_name', det.get('brand', ''))}' tanındı ama hiçbir kaynakta bulunamadı.",
            }

        await pipeline.refresh_product(db, product.id)
        await db.refresh(product)

        hidden = await db.scalar(
            select(func.count()).select_from(Experience).where(
                Experience.product_id == product.id,
                Experience.fake_probability >= 0.7,
            )
        )
        verdict = await assistant.should_buy(db, user, product, None, "Fotoğraftaki ürünü almaya değer mi?")

        return {
            "detected": det,
            "product": catalog.card(product),
            "added_to_catalog": added,
            "fake_reviews_removed": hidden,
            "verdict": verdict,
            "price_stats": verdict["signals"]["price_stats"],
            "alternatives": verdict["signals"]["alternatives"],
        }
    finally:
        Path(file_path).unlink(missing_ok=True)
