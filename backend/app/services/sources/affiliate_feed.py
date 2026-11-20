"""Affiliate ürün feed'i (JSON) adaptörü.

Affiliate ağları (ör. pazar yeri ortaklık programları) ürün feed'lerini
JSON olarak sunar. Beklenen biçim:
[{"id","name","brand","price","url","affiliate_url","images":[],"specs":{},"category","seller"}]
"""
from __future__ import annotations

import time

import httpx

from ...config import get_settings
from .base import FoundProduct, SourceAdapter

_CACHE: dict[str, tuple[float, list]] = {}


class AffiliateFeed(SourceAdapter):
    name = "affiliate"

    @property
    def urls(self) -> list[str]:
        return [u.strip() for u in get_settings().affiliate_feed_urls.split(",") if u.strip()]

    @property
    def enabled(self) -> bool:
        return bool(self.urls)

    async def _load(self, url: str) -> list:
        hit = _CACHE.get(url)
        if hit and time.time() - hit[0] < 3600:
            return hit[1]
        async with httpx.AsyncClient(timeout=60) as c:
            r = await c.get(url)
            r.raise_for_status()
            data = r.json()
        _CACHE[url] = (time.time(), data)
        return data

    async def search(self, query: str, limit: int = 10) -> list[FoundProduct]:
        terms = [t for t in query.lower().split() if len(t) > 1]
        out = []
        for u in self.urls:
            for it in await self._load(u):
                hay = f"{it.get('brand','')} {it.get('name','')}".lower()
                if all(t in hay for t in terms):
                    out.append(FoundProduct(
                        source=self.name, external_id=str(it["id"]), name=it["name"], brand=it.get("brand"),
                        price=float(it["price"]), url=it["url"], images=it.get("images", []),
                        specs=it.get("specs", {}), category_hint=it.get("category"), seller=it.get("seller"),
                        affiliate_url=it.get("affiliate_url")))
                    if len(out) >= limit:
                        return out
        return out
