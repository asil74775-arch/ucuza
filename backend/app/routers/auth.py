from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import get_settings
from ..core.security import create_token, current_user, hash_password, verify_password
from ..db import get_db
from ..models import TasteProfile, User
from ..services.matching import TASTE_TAGS

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=2, max_length=80)
    interests: list[str] = []  # onboarding'de seçilen zevk etiketleri
    accept_terms: bool = False  # Kullanım Koşulları + Gizlilik/Aydınlatma metni (zorunlu)
    age_confirmed: bool = False  # 18 yaş ve üzeri (zorunlu)
    ai_consent: bool = False  # KVKK açık rıza — yurt dışı yapay zeka aktarımı (İSTEĞE BAĞLI)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


def user_out(u: User) -> dict:
    return {"id": u.id, "email": u.email, "display_name": u.display_name, "avatar_url": u.avatar_url,
            "ai_consent": u.ai_consent, "is_admin": u.is_admin, "terms_version": u.terms_version,
            "terms_outdated": u.terms_version != get_settings().terms_version}


@router.post("/register")
async def register(body: RegisterIn, db: AsyncSession = Depends(get_db)):
    if not body.accept_terms:
        raise HTTPException(400, "Devam etmek için Kullanım Koşulları ve Gizlilik Politikası'nı kabul etmelisiniz")
    if not body.age_confirmed:
        raise HTTPException(400, "Dengi'yi kullanmak için 18 yaşından büyük olmalısınız")
    if await db.scalar(select(User).where(User.email == body.email.lower())):
        raise HTTPException(409, "Bu e-posta zaten kayıtlı")
    now = datetime.now(timezone.utc)
    u = User(email=body.email.lower(), password_hash=hash_password(body.password), display_name=body.display_name,
             terms_version=get_settings().terms_version, terms_accepted_at=now, age_confirmed=True,
             ai_consent=body.ai_consent, ai_consent_at=now if body.ai_consent else None)
    db.add(u)
    await db.flush()
    weights = {t: (0.8 if t in body.interests else 0.3) for t in TASTE_TAGS}
    db.add(TasteProfile(user_id=u.id, weights=weights,
                        price_sensitivity=0.8 if "budget" in body.interests else 0.3 if "premium" in body.interests else 0.5))
    await db.commit()
    return {"token": create_token(u.id), "user": user_out(u)}


@router.post("/login")
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
    u = await db.scalar(select(User).where(User.email == body.email.lower()))
    if not u or not verify_password(body.password, u.password_hash):
        raise HTTPException(401, "E-posta veya şifre hatalı")
    return {"token": create_token(u.id), "user": user_out(u)}


@router.get("/me")
async def me(user: User = Depends(current_user)):
    return user_out(user)


@router.delete("/me")
async def delete_account(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """Google Play zorunluluğu: uygulama içinden hesap ve verilerin silinmesi."""
    await db.delete(user)
    await db.commit()
    return {"deleted": True}


@router.post("/accept-terms")
async def accept_terms(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)):
    """Koşullar güncellendiğinde yeni sürümün kabulü."""
    user.terms_version = get_settings().terms_version
    user.terms_accepted_at = datetime.now(timezone.utc)
    await db.commit()
    return user_out(user)
