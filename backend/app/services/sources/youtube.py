"""YouTube Data API v3 — inceleme videolarının yorumları (resmi API)."""
from __future__ import annotations

from datetime import datetime

import httpx

from ...config import get_settings
from .base import FoundReview, SourceAdapter

API = "https://www.googleapis.com/youtube/v3"


class YouTubeComments(SourceAdapter):
    name = "youtube"

    @property
    def enabled(self) -> bool:
        return bool(get_settings().youtube_api_key)

    async def reviews(self, product_name: str, external_ids: dict, limit: int = 100) -> list[FoundReview]:
        key = get_settings().youtube_api_key
        out: list[FoundReview] = []
        async with httpx.AsyncClient(timeout=30) as c:
            s = await c.get(f"{API}/search", params={
                "part": "snippet", "q": f"{product_name} inceleme", "type": "video",
                "maxResults": 3, "relevanceLanguage": "tr", "key": key})
            s.raise_for_status()
            for v in s.json().get("items", []):
                vid = v["id"]["videoId"]
                ct = await c.get(f"{API}/commentThreads", params={
                    "part": "snippet", "videoId": vid, "maxResults": 50, "order": "relevance",
                    "textFormat": "plainText", "key": key})
                if ct.status_code != 200:
                    continue
                for it in ct.json().get("items", []):
                    sn = it["snippet"]["topLevelComment"]["snippet"]
                    out.append(FoundReview(self.name, it["id"], sn.get("authorDisplayName", "Anonim"),
                                           sn.get("textDisplay", ""), None,
                                           datetime.fromisoformat(sn["publishedAt"].replace("Z", "+00:00"))))
                    if len(out) >= limit:
                        return out
        return out
