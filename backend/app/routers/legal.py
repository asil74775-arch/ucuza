"""Yasal metinler (herkese açık web sayfaları) ve hak ihlali / itiraz / KVKK başvuruları.

Play Store'un istediği gizlilik politikası ve hesap silme adresleri buradan sunulur:
  https://api.ucuza.com/legal/gizlilik   https://api.ucuza.com/legal/hesap-silme
"""
import html
import re
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..core.security import current_user
from ..db import get_db
from ..models import Answer, Experience, LegalNotice, Question, User

router = APIRouter(tags=["legal"])
LEGAL_DIR = Path(__file__).resolve().parents[2] / "legal"
DOCS = {
    "gizlilik": "Gizlilik Politikası ve KVKK Aydınlatma Metni",
    "kosullar": "Kullanım Koşulları",
    "acik-riza": "Açık Rıza Metni",
    "yontem": "Puanlama Yöntemi",
    "hesap-silme": "Hesap ve Veri Silme",
}


def render_text(slug: str) -> str:
    s = get_settings()
    note = ("Faturalandırılan (ücretli) Gemini hizmetini kullanıyoruz; Google bu içerikleri kendi modellerini "
            "eğitmek için kullanmaz." if s.gemini_paid_tier else
            "Not: Google, ücretsiz hizmet koşulları kapsamında gönderilen içerikleri kendi hizmetlerini geliştirmek "
            "için de kullanabilir. Hassas bilgi paylaşmayın.")
    raw = (LEGAL_DIR / f"{slug}.md").read_text(encoding="utf-8")
    return raw.format(operator_name=s.operator_name, operator_address=s.operator_address,
                      contact_email=s.contact_email, terms_version=s.terms_version, gemini_training_note=note)


def md_to_html(md: str) -> str:
    out, in_list = [], False
    for line in md.splitlines():
        t = html.escape(line.strip())
        t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
        t = re.sub(r"\*(.+?)\*", r"<i>\1</i>", t)
        is_item = t.startswith("- ") or re.match(r"^\d+\. ", t)
        if in_list and not is_item:
            out.append("</ul>")
            in_list = False
        if t.startswith("## "):
            out.append(f"<h2>{t[3:]}</h2>")
        elif t.startswith("# "):
            out.append(f"<h1>{t[2:]}</h1>")
        elif is_item:
            if not in_list:
                out.append("<ul>")
                in_list = True
            item = re.sub(r"^(- |\d+\. )", "", t)
            out.append(f"<li>{item}</li>")
        elif t:
            out.append(f"<p>{t}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


PAGE = """<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} — Ucuza.com</title>
<style>body{{font-family:system-ui,sans-serif;max-width:760px;margin:0 auto;padding:16px;line-height:1.6;color:#1a1a1a}}
h1{{color:#5B3DF5}}a{{color:#5B3DF5}}nav a{{margin-right:12px}}</style></head><body>
<nav>{nav}</nav>{body}</body></html>"""


@router.get("/legal", response_class=HTMLResponse)
async def legal_index():
    links = "".join(f'<li><a href="/legal/{k}">{v}</a></li>' for k, v in DOCS.items())
    return PAGE.format(title="Yasal", nav="", body=f"<h1>Ucuza.com yasal metinler</h1><ul>{links}</ul>")


@router.get("/legal/{slug}", response_class=HTMLResponse)
async def legal_page(slug: str):
    if slug not in DOCS:
        raise HTTPException(404)
    nav = "".join(f'<a href="/legal/{k}">{v}</a>' for k, v in DOCS.items())
    return PAGE.format(title=DOCS[slug], nav=nav, body=md_to_html(render_text(slug)))


@router.get("/legal-json/{slug}")
async def legal_json(slug: str):
    if slug not in DOCS:
        raise HTTPException(404)
    return {"title": DOCS[slug], "markdown": render_text(slug), "version": get_settings().terms_version}


# ---------------------------------------------------------------- Bildirim / itiraz
class NoticeIn(BaseModel):
    kind: str = Field(pattern="^(icerik_kaldirma|marka_itirazi|kvkk_basvurusu|diger)$")
    name: str = Field(min_length=2, max_length=200)
    email: EmailStr
    target_type: str | None = Field(None, pattern="^(product|experience|question|answer|user)$")
    target_id: int | None = None
    description: str = Field(min_length=10, max_length=5000)


@router.post("/legal/notices")
async def create_notice(body: NoticeIn, db: AsyncSession = Depends(get_db)):
    """Giriş gerekmez: markalar, hak sahipleri ve kullanıcı olmayanlar da bildirim yapabilir."""
    n = LegalNotice(**body.model_dump())
    db.add(n)
    await db.commit()
    return {"id": n.id, "message": "Bildiriminiz alındı. En geç 48 saat içinde incelenecek ve e-posta ile yanıt verilecek."}


async def admin(user: User = Depends(current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(403)
    return user


@router.get("/admin/notices")
async def list_notices(status: str = "open", _: User = Depends(admin), db: AsyncSession = Depends(get_db)):
    rows = (await db.scalars(select(LegalNotice).where(LegalNotice.status == status)
                             .order_by(LegalNotice.created_at))).all()
    now = datetime.now(timezone.utc)
    return [{"id": n.id, "kind": n.kind, "name": n.name, "email": n.email, "target_type": n.target_type,
             "target_id": n.target_id, "description": n.description, "created_at": n.created_at.isoformat(),
             "hours_open": round((now - n.created_at.replace(tzinfo=n.created_at.tzinfo or timezone.utc))
                                 .total_seconds() / 3600, 1)} for n in rows]


class ResolveIn(BaseModel):
    accept: bool
    hide_target: bool = False  # kabulde hedef kullanıcı içeriğini gizle
    resolution: str = ""


@router.post("/admin/notices/{nid}")
async def resolve_notice(nid: int, body: ResolveIn, _: User = Depends(admin), db: AsyncSession = Depends(get_db)):
    n = await db.get(LegalNotice, nid)
    if not n:
        raise HTTPException(404)
    n.status = "accepted" if body.accept else "rejected"
    n.resolution = body.resolution
    model = {"experience": Experience, "question": Question, "answer": Answer}.get(n.target_type or "")
    if body.accept and body.hide_target and model and n.target_id:
        obj = await db.get(model, n.target_id)
        if obj:
            obj.is_hidden = True
    await db.commit()
    return {"ok": True, "status": n.status}


@router.get("/admin/reports")
async def list_reports(_: User = Depends(admin), db: AsyncSession = Depends(get_db)):
    from ..models import Report
    rows = (await db.scalars(select(Report).where(Report.status == "open").order_by(Report.created_at))).all()
    return [{"id": r.id, "target_type": r.target_type, "target_id": r.target_id, "reason": r.reason,
             "created_at": r.created_at.isoformat()} for r in rows]
