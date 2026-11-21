"""Bir kullanıcıyı yönetici yapar (itiraz ve şikayetleri inceleyebilmek için).
Kullanım:  python -m scripts.make_admin sizin@eposta.com"""
import asyncio
import sys

from sqlalchemy import select

from app.db import SessionLocal, init_models
from app.models import User


async def main(email: str) -> None:
    await init_models()
    async with SessionLocal() as db:
        u = await db.scalar(select(User).where(User.email == email.lower()))
        if not u:
            sys.exit("Bu e-postayla kayıtlı kullanıcı yok. Önce uygulamadan kayıt olun.")
        u.is_admin = True
        await db.commit()
        print(f"{email} artık yönetici.")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
