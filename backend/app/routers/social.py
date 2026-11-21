"""Kıyaslio kullanıcı yorumları (Keşfet + Bizden Alanlar), Topluluk Soru-Cevap, şikayet/engelleme.
Uygulamadaki tek yorum kaynağı budur; dış platformlardan yorum metni alınmaz."""
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import current_user, optional_user
from ..config import get_settings
from ..db import SessionLocal, get_db
from ..models import (
    Answer, Block, Experience, ExperienceLike, Ownership, Product, Question, Report, User,
)
from ..services import fake_reviews, pipeline, storage
from ..services.realtime import hub

router = APIRouter(tags=["social"])
BANNED = ["http://", "https://", "whatsapp", "telegram"]  # spam/yönlendirme filtresi (basit)


def clean(text: str) -> str:
    t = text.strip()
    if any(b in t.lower() for b in BANNED):
        raise HTTPException(400, "Bağlantı veya harici iletişim bilgisi paylaşılamaz")
    return t


async def blocked_ids(db, user: User | None) -> set[int]:
    if not user:
        return set()
    return set((await db.scalars(select(Block.blocked_id).where(Block.blocker_id == user.id))).all())


async def reanalyze(product_id: int) -> None:
    """Yeni/silinen yorumdan sonra: AI analizi, sahte yorum tespiti, kronik sorunlar, puan ve rozetler."""
    async with SessionLocal() as db:
        p = await db.get(Product, product_id)
        if p:
            await pipeline.analyze_reviews(db, product_id)
            await pipeline.rescore_category(db, p.category_id)


def exp_out(e: Experience, liked: bool = False) -> dict:
    return {"id": e.id, "text": e.text, "rating": e.rating, "media": e.media, "verified_purchase": e.verified_purchase,
            "ai_stars": e.ai_stars, "complaints": e.complaints or [],
            "suspicious": e.fake_probability >= get_settings().fake_warn_threshold, "fake_reasons": e.fake_reasons or [],
            "like_count": e.like_count, "liked": liked, "created_at": e.created_at.isoformat(),
            "user": {"id": e.user.id, "name": e.user.display_name, "avatar": e.user.avatar_url},
            "product": {"id": e.product.id, "name": e.product.name, "image": (e.product.images or [None])[0]}}


@router.post("/experiences")
async def create_experience(
    bg: BackgroundTasks,
    product_id: int = Form(...), text: str = Form(..., max_length=1000), rating: int = Form(..., ge=1, le=5),
    files: list[UploadFile] = File(default=[]), user: User = Depends(current_user), db: AsyncSession = Depends(get_db),
):
    if len(files) > 6:
        raise HTTPException(400, "En fazla 6 medya")
    if not await db.get(Product, product_id):
        raise HTTPException(404)
    if await db.scalar(select(Experience.id).where(Experience.user_id == user.id, Experience.product_id == product_id)):
        raise HTTPException(409, "Bu ürüne zaten yorum yaptınız. Mevcut yorumunuzu silip yeniden yazabilirsiniz.")
    media = []
    for f in files:
        _, url, kind = await storage.save_upload(f, "experiences")
        media.append({"type": kind, "url": url})
    owner = await db.get(Ownership, (user.id, product_id))
    if not owner:
        db.add(Ownership(user_id=user.id, product_id=product_id))
    body = clean(text)
    e = Experience(user_id=user.id, product_id=product_id, text=body, rating=rating, media=media,
                   verified_purchase=bool(owner and owner.verified), content_hash=fake_reviews.content_hash(body))
    db.add(e)
    await db.commit()
    await db.refresh(e)
    bg.add_task(reanalyze, product_id)
    return exp_out(e)


async def _feed(db, user, stmt, limit, offset):
    blocked = await blocked_ids(db, user)
    rows = (await db.scalars(stmt.where(Experience.is_hidden.is_(False)).order_by(Experience.created_at.desc())
                             .offset(offset).limit(limit))).unique().all()
    liked = set()
    if user:
        liked = set((await db.scalars(select(ExperienceLike.experience_id).where(
            ExperienceLike.user_id == user.id))).all())
    return [exp_out(e, e.id in liked) for e in rows if e.user_id not in blocked]


@router.get("/explore")
async def explore(limit: int = 20, offset: int = 0, db: AsyncSession = Depends(get_db),
                  user: User | None = Depends(optional_user)):
    """Ana sayfadaki 'Keşfet' menüsü."""
    return await _feed(db, user, select(Experience), limit, offset)


@router.get("/products/{pid}/experiences")
async def product_experiences(pid: int, limit: int = 20, offset: int = 0, db: AsyncSession = Depends(get_db),
                              user: User | None = Depends(optional_user)):
    """Ürün sayfasındaki 'Bizden Alanlar' bölümü."""
    return await _feed(db, user, select(Experience).where(Experience.product_id == pid), limit, offset)


@router.post("/experiences/{eid}/like")
async def like(eid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    e = await db.get(Experience, eid)
    if not e:
        raise HTTPException(404)
    existing = await db.get(ExperienceLike, (user.id, eid))
    if existing:
        await db.delete(existing)
        e.like_count = max(0, e.like_count - 1)
    else:
        db.add(ExperienceLike(user_id=user.id, experience_id=eid))
        e.like_count += 1
    await db.commit()
    return {"liked": not existing, "like_count": e.like_count}


@router.delete("/experiences/{eid}")
async def delete_experience(eid: int, bg: BackgroundTasks, user: User = Depends(current_user),
                            db: AsyncSession = Depends(get_db)):
    e = await db.get(Experience, eid)
    if not e or e.user_id != user.id:
        raise HTTPException(404)
    pid = e.product_id
    await db.delete(e)
    await db.commit()
    bg.add_task(reanalyze, pid)
    return {"ok": True}


# ---------------------------------------------------------------- Soru-Cevap
class QIn(BaseModel):
    text: str = Field(min_length=5, max_length=600)


class AIn(BaseModel):
    text: str = Field(min_length=2, max_length=1000)


def q_out(q: Question, blocked: set[int]) -> dict:
    return {"id": q.id, "text": q.text, "created_at": q.created_at.isoformat(),
            "user": {"id": q.user.id, "name": q.user.display_name},
            "answers": sorted([{"id": a.id, "text": a.text, "is_owner": a.is_owner, "helpful_count": a.helpful_count,
                                "created_at": a.created_at.isoformat(),
                                "user": {"id": a.user.id, "name": a.user.display_name}}
                               for a in q.answers if not a.is_hidden and a.user_id not in blocked],
                              key=lambda a: (-a["is_owner"], -a["helpful_count"]))}


@router.get("/products/{pid}/questions")
async def questions(pid: int, db: AsyncSession = Depends(get_db), user: User | None = Depends(optional_user)):
    blocked = await blocked_ids(db, user)
    rows = (await db.scalars(select(Question).where(Question.product_id == pid, Question.is_hidden.is_(False))
                             .order_by(Question.created_at.desc()))).unique().all()
    owners = await db.scalar(select(func.count()).select_from(Ownership)
                             .where(Ownership.product_id == pid))
    return {"owner_count": owners, "questions": [q_out(q, blocked) for q in rows if q.user_id not in blocked]}


@router.post("/products/{pid}/questions")
async def ask(pid: int, body: QIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    q = Question(product_id=pid, user_id=user.id, text=clean(body.text))
    db.add(q)
    await db.commit()
    # Ürün sahiplerine gerçek zamanlı bildirim: "Sahip olduğun ürün hakkında soru var"
    owner_ids = (await db.scalars(select(Ownership.user_id).where(Ownership.product_id == pid,
                                                                  Ownership.user_id != user.id))).all()
    await hub.send(list(owner_ids), {"type": "question", "product_id": pid, "question_id": q.id, "text": q.text})
    return {"id": q.id}


@router.post("/questions/{qid}/answers")
async def answer(qid: int, body: AIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    q = await db.get(Question, qid)
    if not q:
        raise HTTPException(404)
    is_owner = bool(await db.get(Ownership, (user.id, q.product_id)))
    a = Answer(question_id=qid, user_id=user.id, text=clean(body.text), is_owner=is_owner)
    db.add(a)
    await db.commit()
    await hub.send([q.user_id], {"type": "answer", "question_id": qid, "text": a.text})
    return {"id": a.id, "is_owner": is_owner}


@router.post("/answers/{aid}/helpful")
async def helpful(aid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    a = await db.get(Answer, aid)
    if not a:
        raise HTTPException(404)
    a.helpful_count += 1
    await db.commit()
    return {"helpful_count": a.helpful_count}


# ---------------------------------------------------------------- Moderasyon
class ReportIn(BaseModel):
    target_type: str = Field(pattern="^(experience|question|answer|message|user)$")
    target_id: int
    reason: str = Field(min_length=3, max_length=300)


@router.post("/reports")
async def report(body: ReportIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    db.add(Report(reporter_id=user.id, **body.model_dump()))
    # 3+ şikayet alan içerik otomatik gizlenir, moderatör incelemesine düşer
    count = len((await db.scalars(select(Report).where(Report.target_type == body.target_type,
                                                       Report.target_id == body.target_id))).all()) + 1
    model = {"experience": Experience, "question": Question, "answer": Answer}.get(body.target_type)
    if model and count >= 3:
        obj = await db.get(model, body.target_id)
        if obj:
            obj.is_hidden = True
    await db.commit()
    return {"ok": True}


@router.post("/blocks/{uid}")
async def block(uid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    if uid != user.id and not await db.get(Block, (user.id, uid)):
        db.add(Block(blocker_id=user.id, blocked_id=uid))
        await db.commit()
    return {"ok": True}


@router.delete("/blocks/{uid}")
async def unblock(uid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    b = await db.get(Block, (user.id, uid))
    if b:
        await db.delete(b)
        await db.commit()
    return {"ok": True}
