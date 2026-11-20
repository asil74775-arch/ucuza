"""Kullanıcılar arası mesajlaşma: REST (geçmiş) + WebSocket (anlık)."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import current_user, decode_token
from ..db import SessionLocal, get_db
from ..models import Block, Conversation, ConversationMember, Message, User
from ..services.realtime import hub

router = APIRouter(tags=["messages"])


class StartIn(BaseModel):
    user_id: int
    product_id: int | None = None
    text: str | None = None


class SendIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


def m_out(m: Message) -> dict:
    return {"id": m.id, "conversation_id": m.conversation_id, "sender_id": m.sender_id, "text": m.text,
            "media_url": m.media_url, "created_at": m.created_at.isoformat()}


async def _member_conv(db, cid: int, user: User) -> Conversation:
    c = await db.get(Conversation, cid)
    if not c or user.id not in [m.user_id for m in c.members]:
        raise HTTPException(404)
    return c


async def _send(db: AsyncSession, conv: Conversation, sender: User, text: str) -> Message:
    others = [m.user_id for m in conv.members if m.user_id != sender.id]
    if await db.scalar(select(Block).where(Block.blocker_id.in_(others), Block.blocked_id == sender.id)):
        raise HTTPException(403, "Bu kullanıcıya mesaj gönderemezsiniz")
    msg = Message(conversation_id=conv.id, sender_id=sender.id, text=text.strip())
    conv.last_message_at = datetime.now(timezone.utc)
    db.add(msg)
    await db.commit()
    await hub.send([m.user_id for m in conv.members], {"type": "message", "message": m_out(msg)})
    return msg


@router.get("/conversations")
async def conversations(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    convs = (await db.scalars(select(Conversation).join(ConversationMember)
                              .where(ConversationMember.user_id == user.id)
                              .order_by(Conversation.last_message_at.desc()))).unique().all()
    out = []
    for c in convs:
        last = await db.scalar(select(Message).where(Message.conversation_id == c.id).order_by(Message.id.desc()).limit(1))
        me = next(m for m in c.members if m.user_id == user.id)
        unread = len((await db.scalars(select(Message.id).where(
            Message.conversation_id == c.id, Message.created_at > me.last_read_at, Message.sender_id != user.id))).all())
        other = next((m.user for m in c.members if m.user_id != user.id), None)
        out.append({"id": c.id, "product_id": c.product_id, "unread": unread,
                    "other": {"id": other.id, "name": other.display_name, "avatar": other.avatar_url,
                              "online": hub.online(other.id)} if other else None,
                    "last_message": m_out(last) if last else None})
    return out


@router.post("/conversations")
async def start(body: StartIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    if body.user_id == user.id or not await db.get(User, body.user_id):
        raise HTTPException(400, "Geçersiz alıcı")
    mine = set((await db.scalars(select(ConversationMember.conversation_id).where(ConversationMember.user_id == user.id))).all())
    theirs = set((await db.scalars(select(ConversationMember.conversation_id).where(ConversationMember.user_id == body.user_id))).all())
    common = mine & theirs
    if common:
        conv = await db.get(Conversation, next(iter(common)))
    else:
        conv = Conversation(product_id=body.product_id)
        db.add(conv)
        await db.flush()
        db.add_all([ConversationMember(conversation_id=conv.id, user_id=user.id),
                    ConversationMember(conversation_id=conv.id, user_id=body.user_id)])
        await db.commit()
        conv = await db.get(Conversation, conv.id)
        await db.refresh(conv, ["members"])
    if body.text:
        await _send(db, conv, user, body.text)
    return {"id": conv.id}


@router.get("/conversations/{cid}/messages")
async def history(cid: int, before_id: int | None = None, limit: int = Query(40, le=100),
                  user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    c = await _member_conv(db, cid, user)
    stmt = select(Message).where(Message.conversation_id == cid)
    if before_id:
        stmt = stmt.where(Message.id < before_id)
    rows = (await db.scalars(stmt.order_by(Message.id.desc()).limit(limit))).all()
    me = next(m for m in c.members if m.user_id == user.id)
    me.last_read_at = datetime.now(timezone.utc)
    await db.commit()
    return [m_out(m) for m in reversed(rows)]


@router.post("/conversations/{cid}/messages")
async def send(cid: int, body: SendIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    c = await _member_conv(db, cid, user)
    return m_out(await _send(db, c, user, body.text))


@router.websocket("/ws")
async def ws(websocket: WebSocket, token: str):
    """İstemci: wss://api/ws?token=JWT.  Gönder: {"type":"send","conversation_id":1,"text":"..."}
    Alır: {"type":"message"|"typing"|"question"|"answer", ...}"""
    try:
        uid = decode_token(token)
    except HTTPException:
        await websocket.close(code=4401)
        return
    await hub.connect(uid, websocket)
    try:
        while True:
            data = await websocket.receive_json()
            async with SessionLocal() as db:
                user = await db.get(User, uid)
                if data.get("type") == "send":
                    try:
                        conv = await _member_conv(db, int(data["conversation_id"]), user)
                        await _send(db, conv, user, str(data.get("text", ""))[:2000])
                    except HTTPException as e:
                        await websocket.send_json({"type": "error", "detail": e.detail})
                elif data.get("type") == "typing":
                    conv = await _member_conv(db, int(data["conversation_id"]), user)
                    await hub.send([m.user_id for m in conv.members if m.user_id != uid],
                                   {"type": "typing", "conversation_id": conv.id, "user_id": uid})
    except WebSocketDisconnect:
        hub.disconnect(uid, websocket)
