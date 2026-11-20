"""Medya depolama. Varsayılan: yerel disk (MEDIA_ROOT) + /media statik servis.
Üretimde MEDIA_ROOT bir S3/GCS FUSE bağlantısı ya da CDN arkasında bir volume olabilir."""
from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile

from ..config import get_settings

ALLOWED = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp",
           "video/mp4": ".mp4", "video/quicktime": ".mov", "video/webm": ".webm"}


async def save_upload(f: UploadFile, folder: str) -> tuple[str, str, str]:
    """(mutlak dosya yolu, herkese açık URL, medya tipi) döner."""
    s = get_settings()
    ext = ALLOWED.get(f.content_type or "")
    if not ext:
        raise HTTPException(415, "Desteklenmeyen dosya türü")
    root = Path(s.media_root) / folder
    root.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ext}"
    path = root / name
    size, limit = 0, s.max_upload_mb * 1024 * 1024
    with path.open("wb") as out:
        while chunk := await f.read(1024 * 1024):
            size += len(chunk)
            if size > limit:
                out.close()
                path.unlink(missing_ok=True)
                raise HTTPException(413, f"Dosya {s.max_upload_mb} MB sınırını aşıyor")
            out.write(chunk)
    kind = "video" if f.content_type.startswith("video") else "image"
    return str(path), f"{s.public_base_url}/media/{folder}/{name}", kind
