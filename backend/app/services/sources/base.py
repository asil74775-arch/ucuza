"""Kaynak adaptör arayüzü.

Her adaptör LİSANSLI/RESMİ bir kaynağı temsil eder (affiliate feed, SerpAPI
Google Shopping, YouTube Data API). Yeni pazar yeri eklemek = yeni bir
SourceAdapter alt sınıfı yazıp REGISTRY'ye eklemek.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


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


@dataclass
class FoundReview:
    source: str
    external_id: str
    author: str
    text: str
    rating: float | None
    posted_at: datetime


class SourceAdapter:
    name = "base"

    @property
    def enabled(self) -> bool:
        return False

    async def search(self, query: str, limit: int = 10) -> list[FoundProduct]:
        return []

    async def reviews(self, product_name: str, external_ids: dict, limit: int = 100) -> list[FoundReview]:
        return []
