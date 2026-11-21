from fastapi import APIRouter, BackgroundTasks, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import current_user
from ..db import get_db
from ..models import AiMessage, AiSession, Product, User, VideoJob
from ..services import assistant, catalog, photo_search, storage, video
from ..services.gemini import gemini

router = APIRouter(prefix="/ai", tags=["ai"])


class SessionIn(BaseModel):
    mode: str = Field("general", pattern="^(general|should_buy|mission|project)$")


class ChatIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class ShouldBuyIn(BaseModel):
    product_id: int | None = None
    product_query: str | None = None
    budget: float | None = None
    needs: str = ""


class MissionIn(BaseModel):
    text: str = Field(min_length=3, max_length=500)


class ProjectIn(BaseModel):
    title: str
    description: str
    budget: float | None = None
    add_to_cart: bool = True


class DuelIn(BaseModel):
    a_id: int | None = None
    b_id: int | None = None
    a_query: str | None = None
    b_query: str | None = None


def msg_out(m: AiMessage) -> dict:
    return {"id": m.id, "role": m.role, "text": m.text, "data": m.data, "created_at": m.created_at.isoformat()}


@router.get("/status")
async def status():
    return {"ai_enabled": gemini.available, "model": gemini.model,
            "disclaimer": "Yapay zeka yanıtları bilgilendirme amaçlıdır, hata içerebilir ve satın alma tavsiyesi değildir."}


@router.post("/sessions")
async def new_session(body: SessionIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    s = AiSession(user_id=user.id, mode=body.mode)
    db.add(s)
    await db.commit()
    return {"id": s.id, "mode": s.mode}


@router.get("/sessions/{sid}/messages")
async def messages(sid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    s = await db.get(AiSession, sid)
    if not s or s.user_id != user.id:
        raise HTTPException(404)
    rows = (await db.scalars(select(AiMessage).where(AiMessage.session_id == sid).order_by(AiMessage.id))).all()
    return [msg_out(m) for m in rows]


@router.post("/sessions/{sid}/chat")
async def chat(sid: int, body: ChatIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    s = await db.get(AiSession, sid)
    if not s or s.user_id != user.id:
        raise HTTPException(404)
    return msg_out(await assistant.chat(db, user, s, body.text))


async def _resolve(db: AsyncSession, pid: int | None, query: str | None) -> Product:
    if pid:
        p = await db.get(Product, pid)
    else:
        res = await catalog.search(db, q=query, limit=1, personalize=False) if query else []
        p = await db.get(Product, res[0]["id"]) if res else None
        if not p and query:
            from ..services import pipeline
            found = await pipeline.discover(db, query, limit=1)
            p = found[0] if found else None
    if not p:
        raise HTTPException(404, "Ürün bulunamadı")
    return p


@router.post("/should-buy")
async def should_buy(body: ShouldBuyIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    p = await _resolve(db, body.product_id, body.product_query)
    return {"product": catalog.card(p), **await assistant.should_buy(db, user, p, body.budget, body.needs)}


@router.post("/mission")
async def mission(body: MissionIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    return await assistant.mission(db, user, body.text)


@router.post("/project")
async def project(body: ProjectIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    return await assistant.project_plan(db, user, body.title, body.description, body.budget, body.add_to_cart)


@router.post("/duel")
async def duel(body: DuelIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    a = await _resolve(db, body.a_id, body.a_query)
    b = await _resolve(db, body.b_id, body.b_query)
    if a.id == b.id:
        raise HTTPException(400, "Aynı ürün karşılaştırılamaz")
    res = await catalog.duel(db, a, b)
    res["commentary"] = await assistant.duel_commentary(res)
    return res


@router.post("/video")
async def upload_video(bg: BackgroundTasks, file: UploadFile = File(...), user: User = Depends(current_user),
                       db: AsyncSession = Depends(get_db)):
    if not user.ai_consent:
        raise HTTPException(403, "Video analizi için Profil > Gizlilik bölümünden yapay zeka açık rızası vermelisiniz.")
    path, _, kind = await storage.save_upload(file, "videos")
    if kind != "video":
        raise HTTPException(415, "Lütfen bir video yükleyin")
    job = VideoJob(user_id=user.id, file_path=path)
    db.add(job)
    await db.commit()
    bg.add_task(video.process, job.id)
    return {"job_id": job.id, "status": job.status}


@router.get("/video/{jid}")
async def video_status(jid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    j = await db.get(VideoJob, jid)
    if not j or j.user_id != user.id:
        raise HTTPException(404)
    return {"job_id": j.id, "status": j.status, "stage": j.stage, "result": j.result, "error": j.error}


@router.post("/photo-search")
async def photo_search_endpoint(
    file: UploadFile = File(...),
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fotoğraf yükle → ürünü tanı → katalogda bul/ekle → verdict döndür."""
    if not user.ai_consent:
        raise HTTPException(403, "Fotoğraf arama için Profil > Gizlilik bölümünden yapay zeka açık rızası vermelisiniz.")
    path, _, kind = await storage.save_upload(file, "photo_search")
    if kind != "image":
        raise HTTPException(415, "Lütfen bir fotoğraf yükleyin (JPEG, PNG veya WebP)")
    return await photo_search.search(db, user, path)
