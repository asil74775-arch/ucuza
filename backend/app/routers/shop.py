from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import current_user
from ..db import get_db
from ..models import CartItem, Ownership, Project, User
from ..services import catalog

router = APIRouter(tags=["shop"])


class CartIn(BaseModel):
    product_id: int
    quantity: int = 1
    offer_id: int | None = None


@router.get("/cart")
async def cart(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    items = (await db.scalars(select(CartItem).where(CartItem.user_id == user.id).order_by(CartItem.id))).unique().all()
    projects = {p.id: p.title for p in (await db.scalars(select(Project).where(Project.user_id == user.id))).all()}
    out = [{"id": i.id, "quantity": i.quantity, "note": i.note, "project_id": i.project_id,
            "project_title": projects.get(i.project_id), "product": catalog.card(i.product),
            "line_total": i.product.current_price * i.quantity} for i in items]
    return {"items": out, "total": round(sum(i["line_total"] for i in out), 2)}


@router.post("/cart")
async def add(body: CartIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    db.add(CartItem(user_id=user.id, product_id=body.product_id, quantity=body.quantity, offer_id=body.offer_id))
    await db.commit()
    return {"ok": True}


@router.patch("/cart/{iid}")
async def update(iid: int, body: dict, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    i = await db.get(CartItem, iid)
    if not i or i.user_id != user.id:
        raise HTTPException(404)
    i.quantity = max(1, int(body.get("quantity", i.quantity)))
    await db.commit()
    return {"ok": True}


@router.delete("/cart/{iid}")
async def remove(iid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    i = await db.get(CartItem, iid)
    if not i or i.user_id != user.id:
        raise HTTPException(404)
    await db.delete(i)
    await db.commit()
    return {"ok": True}


@router.get("/projects")
async def projects(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    rows = (await db.scalars(select(Project).where(Project.user_id == user.id).order_by(Project.id.desc()))).all()
    return [{"id": p.id, "title": p.title, "budget": p.budget, "total": p.plan.get("total"),
             "items": p.plan.get("chosen", []), "missing": p.plan.get("missing", [])} for p in rows]


@router.post("/ownership/{pid}")
async def own(pid: int, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """'Bu ürüne sahibim' — Bizden Alanlar ve Soru-Cevap sahip rozeti için."""
    if not await db.get(Ownership, (user.id, pid)):
        db.add(Ownership(user_id=user.id, product_id=pid))
        await db.commit()
    return {"ok": True}


@router.get("/ownership")
async def my_products(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    from ..models import Product
    rows = (await db.scalars(select(Product).join(Ownership, Ownership.product_id == Product.id)
                             .where(Ownership.user_id == user.id))).unique().all()
    return [catalog.card(p) for p in rows]
