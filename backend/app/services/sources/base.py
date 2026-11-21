"""Kaynak adaptör arayüzü.

Her adaptör LİSANSLI/RESMİ bir kaynağı temsil eder (affiliate feed, Google
Shopping). Kaynaklardan YALNIZCA ürün, fiyat ve PUAN (ortalama + sayı) alınır;
yorum metni toplanmaz. Yorumlar yalnızca FiyatRadar kullanıcılarından gelir.
"""
from __future__ import annotations

from dataclasses import dataclass, field

@dataclass
class FoundProduct:
    source: str
    external_id: str
    name: str
    brand: str | None
    price: float | None
    url: str
    images: list[str] = field(default_factory=list)
    specs: dict = field(default_factory=dict)
    description: str = ""
    category_hint: str | None = None
    rating: float | None = None
    rating_count: int | None = None
    seller: str | None = None
    affiliate_url: str | None = None
    rating_source: str | None = None  # puanın ait olduğu platform adı (ör. "Trendyol")


class SourceAdapter:
    name = "base"

    @property
    def enabled(self) -> bool:
        return False

    async def search(self, query: str, limit: int = 10) -> list[FoundProduct]:
        return []
