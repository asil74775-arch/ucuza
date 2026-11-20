"""SerpAPI Google Shopping (lisanslı arama API'si) adaptörü — ürün, fiyat ve yorumlar."""
from __future__ import annotations

from datetime import datetime, timezone

import httpx

from ...config import get_settings
from .base import FoundProduct, FoundReview, SourceAdapter

URL = "https://serpapi.com/search.json"


def _price(v) -> float | None:
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        digits = v.replace("TL", "").replace("₺", "").replace(".", "").replace(",", ".").strip()
        try:
            return float(digits)
        except ValueError:
            return None
    return None


class SerpApiShopping(SourceAdapter):
    name = "google_shopping"

    @property
    def enabled(self) -> bool:
        return bool(get_settings().serpapi_key)

    async def search(self, query: str, limit: int = 10) -> list[FoundProduct]:
        params = {"engine": "google_shopping", "q": query, "gl": "tr", "hl": "tr",
                  "api_key": get_settings().serpapi_key}
        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.get(URL, params=params)
            r.raise_for_status()
            data = r.json()
        out = []
        for it in data.get("shopping_results", [])[:limit]:
            out.append(FoundProduct(
                source=self.name, external_id=str(it.get("product_id") or it.get("position")),
                name=it.get("title", ""), brand=None, price=it.get("extracted_price") or _price(it.get("price")),
                url=it.get("product_link") or it.get("link", ""), images=[i for i in [it.get("thumbnail")] if i],
                rating=it.get("rating"), rating_count=it.get("reviews"), seller=it.get("source"),
            ))
        return out

    async def reviews(self, product_name: str, external_ids: dict, limit: int = 100) -> list[FoundReview]:
        pid = external_ids.get(self.name)
        if not pid:
            return []
        params = {"engine": "google_product", "product_id": pid, "reviews": "1", "gl": "tr", "hl": "tr",
                  "api_key": get_settings().serpapi_key}
        async with httpx.AsyncClient(timeout=30) as c:
            r = await c.get(URL, params=params)
            r.raise_for_status()
            data = r.json()
        out = []
        for i, rv in enumerate(data.get("reviews_results", {}).get("reviews", [])[:limit]):
            try:
                dt = datetime.strptime(rv.get("date", ""), "%B %d, %Y").replace(tzinfo=timezone.utc)
            except ValueError:
                dt = datetime.now(timezone.utc)
            out.append(FoundReview(self.name, f"{pid}-{i}", rv.get("source", "Anonim"),
                                   rv.get("content", ""), rv.get("rating"), dt))
        return out
