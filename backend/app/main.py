import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import get_settings
from .db import init_models
from .routers import ai, auth, catalog, legal, messages, profile, shop, social
from .services.realtime import hub

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_models()  # üretimde: alembic upgrade head
    await hub.start()
    yield


settings = get_settings()
app = FastAPI(title="Dengi.com API", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
Path(settings.media_root).mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=settings.media_root), name="media")

for r in (auth.router, profile.router, catalog.router, ai.router, shop.router, social.router, messages.router, legal.router):
    app.include_router(r)


@app.get("/health")
async def health():
    return {"ok": True, "app": settings.app_name}
