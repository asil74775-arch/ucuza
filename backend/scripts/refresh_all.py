"""Tüm ürünler için periyodik yenileme: teklif/fiyat, yorum toplama, AI analizi, puanlar.
Fiyat geçmişi ve puan geçmişi grafikleri bu iş sayesinde zaman içinde dolar."""
import asyncio
import logging

from sqlalchemy import select

from app.db import SessionLocal, init_models
from app.models import Product
from app.services import pipeline

logging.basicConfig(level=logging.INFO)


async def main() -> None:
    await init_models()
    async with SessionLocal() as db:
        ids = (await db.scalars(select(Product.id).order_by(Product.updated_at))).all()
    for pid in ids:
        async with SessionLocal() as db:
            try:
                p = await db.get(Product, pid)
                await pipeline.record_price(db, p)
                await db.commit()
                logging.info("ürün %s: %s", pid, await pipeline.refresh_product(db, pid))
            except Exception:  # noqa: BLE001
                logging.exception("ürün %s yenilenemedi", pid)
        await asyncio.sleep(1)  # API kotalarına saygı


if __name__ == "__main__":
    asyncio.run(main())
