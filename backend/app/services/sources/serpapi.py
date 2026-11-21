"""SerpAPI Google Shopping adaptörü — ürün, fiyat ve PUAN (yorum metni alınmaz)."""
from __future__ import annotations

import httpx

from ...config import get_settings
from .base import FoundProduct, SourceAdapter

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
                rating_source=it.get("source") or "Google Shopping",
            ))
        return out
