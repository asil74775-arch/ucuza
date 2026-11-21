"""Google Gemini REST istemcisi.

- Ücretsiz katman: gemini-2.5-flash (Google AI Studio anahtarı).
- JSON çıktı modu, fonksiyon çağırma (tool use) ve video/görsel girdisi destekler.
- GEMINI_API_KEY tanımlı değilse `available` False döner; tüm servisler
  bu durumda deterministik kural tabanlı yedeğe düşer (uygulama çökmez).
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import mimetypes
from pathlib import Path
from typing import Any

import httpx

from ..config import get_settings

log = logging.getLogger("binolcbiral.gemini")
BASE = "https://generativelanguage.googleapis.com"


class GeminiError(RuntimeError):
    pass


class GeminiClient:
    def __init__(self) -> None:
        s = get_settings()
        self.key = s.gemini_api_key
        self.model = s.gemini_model

    @property
    def available(self) -> bool:
        return bool(self.key)

    async def _post(self, path: str, body: dict, timeout: float = 90) -> dict:
        url = f"{BASE}{path}"
        headers = {"x-goog-api-key": self.key or "", "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=timeout) as c:
            for attempt in range(4):
                r = await c.post(url, headers=headers, json=body)
                if r.status_code in (429, 500, 503):  # ücretsiz katman hız sınırı -> geri çekil
                    await asyncio.sleep(2 ** attempt)
                    continue
                if r.status_code >= 400:
                    raise GeminiError(f"Gemini {r.status_code}: {r.text[:300]}")
                return r.json()
        raise GeminiError("Gemini hız sınırı aşıldı")

    async def generate(
        self,
        contents: list[dict],
        system: str | None = None,
        json_schema: dict | None = None,
        tools: list[dict] | None = None,
        temperature: float = 0.4,
    ) -> dict:
        body: dict[str, Any] = {
            "contents": contents,
            "generationConfig": {"temperature": temperature},
        }
        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}
        if json_schema:
            body["generationConfig"]["responseMimeType"] = "application/json"
            body["generationConfig"]["responseSchema"] = json_schema
        if tools:
            body["tools"] = [{"functionDeclarations": tools}]
        return await self._post(f"/v1beta/models/{self.model}:generateContent", body)

    @staticmethod
    def text_of(resp: dict) -> str:
        try:
            parts = resp["candidates"][0]["content"]["parts"]
        except (KeyError, IndexError):
            return ""
        return "".join(p.get("text", "") for p in parts)

    async def json(self, prompt: str, schema: dict, system: str | None = None, extra_parts: list | None = None) -> Any:
        parts = [{"text": prompt}] + (extra_parts or [])
        resp = await self.generate([{"role": "user", "parts": parts}], system=system, json_schema=schema, temperature=0.2)
        txt = self.text_of(resp)
        try:
            return json.loads(txt)
        except json.JSONDecodeError as exc:
            raise GeminiError(f"JSON çözümlenemedi: {txt[:200]}") from exc

    async def text(self, prompt: str, system: str | None = None) -> str:
        resp = await self.generate([{"role": "user", "parts": [{"text": prompt}]}], system=system)
        return self.text_of(resp)

    # ---------------------------------------------------------- medya
    async def upload_file(self, path: str) -> dict:
        """Büyük videolar için Files API (resumable upload). Dosya ACTIVE olana kadar bekler."""
        p = Path(path)
        mime = mimetypes.guess_type(p.name)[0] or "video/mp4"
        size = p.stat().st_size
        async with httpx.AsyncClient(timeout=300) as c:
            start = await c.post(
                f"{BASE}/upload/v1beta/files",
                headers={
                    "x-goog-api-key": self.key or "",
                    "X-Goog-Upload-Protocol": "resumable",
                    "X-Goog-Upload-Command": "start",
                    "X-Goog-Upload-Header-Content-Length": str(size),
                    "X-Goog-Upload-Header-Content-Type": mime,
                    "Content-Type": "application/json",
                },
                json={"file": {"display_name": p.name}},
            )
            start.raise_for_status()
            upload_url = start.headers["x-goog-upload-url"]
            up = await c.post(
                upload_url,
                headers={"X-Goog-Upload-Command": "upload, finalize", "X-Goog-Upload-Offset": "0"},
                content=p.read_bytes(),
            )
            up.raise_for_status()
            f = up.json()["file"]
            for _ in range(60):
                if f.get("state") == "ACTIVE":
                    break
                await asyncio.sleep(2)
                g = await c.get(f"{BASE}/v1beta/{f['name']}", headers={"x-goog-api-key": self.key or ""})
                f = g.json()
            return f

    async def media_part(self, path: str) -> dict:
        p = Path(path)
        mime = mimetypes.guess_type(p.name)[0] or "video/mp4"
        if p.stat().st_size < 18 * 1024 * 1024:
            return {"inline_data": {"mime_type": mime, "data": base64.b64encode(p.read_bytes()).decode()}}
        f = await self.upload_file(path)
        return {"file_data": {"mime_type": f.get("mimeType", mime), "file_uri": f["uri"]}}


gemini = GeminiClient()


def ai_ok(user) -> bool:
    """Kullanıcının yazdığı/yüklediği içerik Gemini'ye (yurt dışı) YALNIZCA açık rızasıyla gönderilir.
    Rıza yoksa çağıran servis kural tabanlı yerel moda düşer. Kişisel veri içermeyen istekler
    (ör. iki ürünün teknik verisinin karşılaştırma yorumu) bu kontrole tabi değildir."""
    return gemini.available and bool(getattr(user, "ai_consent", False))
