"""WebSocket bağlantı yöneticisi (kullanıcılar arası mesajlaşma).
Tek sunucuda bellek içi; REDIS_URL varsa Redis pub/sub ile yatay ölçeklenir."""
from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict

from fastapi import WebSocket

from ..config import get_settings

log = logging.getLogger("binolcbiral.ws")


class Hub:
    def __init__(self) -> None:
        self.sockets: dict[int, set[WebSocket]] = defaultdict(set)
        self.redis = None

    async def start(self) -> None:
        url = get_settings().redis_url
        if not url:
            return
        import redis.asyncio as aioredis
        self.redis = aioredis.from_url(url)
        asyncio.create_task(self._listen())

    async def _listen(self) -> None:
        pubsub = self.redis.pubsub()
        await pubsub.subscribe("binolcbiral:ws")
        async for msg in pubsub.listen():
            if msg.get("type") == "message":
                data = json.loads(msg["data"])
                await self._deliver_local(data["user_ids"], data["event"])

    async def connect(self, user_id: int, ws: WebSocket) -> None:
        await ws.accept()
        self.sockets[user_id].add(ws)

    def disconnect(self, user_id: int, ws: WebSocket) -> None:
        self.sockets[user_id].discard(ws)

    def online(self, user_id: int) -> bool:
        return bool(self.sockets.get(user_id))

    async def _deliver_local(self, user_ids: list[int], event: dict) -> None:
        for uid in user_ids:
            for ws in list(self.sockets.get(uid, ())):
                try:
                    await ws.send_json(event)
                except Exception:  # noqa: BLE001
                    self.disconnect(uid, ws)

    async def send(self, user_ids: list[int], event: dict) -> None:
        if self.redis:
            await self.redis.publish("binolcbiral:ws", json.dumps({"user_ids": user_ids, "event": event}, default=str))
        else:
            await self._deliver_local(user_ids, event)


hub = Hub()
