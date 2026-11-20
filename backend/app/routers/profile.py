from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import current_user
from ..db import get_db
from ..models import Product, TasteProfile, User, UserEvent
from ..services import matching

router = APIRouter(prefix="/profile", tags=["profile"])


class TasteIn(BaseModel):
    weights: dict[str, float] | None = None
    price_sensitivity: float | None = None


class EventIn(BaseModel):
    kind: str  # view|like|search|cart|purchase|dismiss
    product_id: int | None = None
    payload: dict = {}


class FcmIn(BaseModel):
    token: str


async def _taste(db, user) -> TasteProfile:
    t = await db.get(TasteProfile, user.id)
    if not t:
        t = TasteProfile(user_id=user.id, weights={k: 0.3 for k in matching.TASTE_TAGS})
        db.add(t)
        await db.flush()
    return t


@router.get("/taste")
async def get_taste(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    t = await _taste(db, user)
    await db.commit()
    return {"labels": matching.TASTE_TAGS, "weights": t.weights, "price_sensitivity": t.price_sensitivity}


@router.put("/taste")
async def put_taste(body: TasteIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    t = await _taste(db, user)
    if body.weights is not None:
        t.weights = {k: max(0.0, min(1.0, v)) for k, v in body.weights.items() if k in matching.TASTE_TAGS}
    if body.price_sensitivity is not None:
        t.price_sensitivity = max(0.0, min(1.0, body.price_sensitivity))
    await db.commit()
    return {"weights": t.weights, "price_sensitivity": t.price_sensitivity}


@router.post("/events")
async def track(body: EventIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """Davranışlardan zevk profilini öğrenir."""
    db.add(UserEvent(user_id=user.id, product_id=body.product_id, kind=body.kind, payload=body.payload))
    if body.product_id:
        p = await db.get(Product, body.product_id)
        if p:
            prices = (await db.scalars(select(Product.current_price).where(Product.category_id == p.category_id))).all()
            t = await _taste(db, user)
            t.weights = matching.update_taste(t.weights, p.tags or [], body.kind,
                                              matching.price_tier(p.current_price, list(prices)))
    await db.commit()
    return {"ok": True}


@router.put("/fcm")
async def fcm(body: FcmIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    user.fcm_token = body.token
    await db.commit()
    return {"ok": True}
