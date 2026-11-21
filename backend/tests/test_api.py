import json

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from scripts.seed import seed


@pytest.fixture(scope="session")
async def client():
    await seed(demo=True)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as c:
        r = await c.post("/auth/register", json={"email": "a@b.co", "password": "sifre1234",
                                                 "display_name": "Ayşe", "interests": ["gaming", "budget"],
                                                 "accept_terms": True, "age_confirmed": True})
        c.headers["Authorization"] = f"Bearer {r.json()['token']}"
        yield c


async def test_home_and_category(client):
    home = (await client.get("/home")).json()
    assert home["sections"] and home["for_you"]
    cats = (await client.get("/categories")).json()
    tel = next(c for c in cats if c["slug"] == "telefon")
    cheap = (await client.get("/products", params={"category_id": tel["id"], "sort": "cheapest"})).json()
    assert cheap[0]["price"] <= cheap[-1]["price"]
    nfc = (await client.get("/products", params={"category_id": tel["id"],
                                                 "specs": json.dumps({"nfc": True, "ram_gb": {"min": 8}})})).json()
    assert all("Generic" not in p["name"] for p in nfc)
    facets = (await client.get(f"/categories/{tel['id']}/facets")).json()
    assert any(f["key"] == "ram_gb" for f in facets["specs"])


async def test_product_detail_history_reviews(client):
    lst = (await client.get("/products", params={"q": "X-Phone"})).json()
    pid = lst[0]["id"]
    d = (await client.get(f"/products/{pid}")).json()
    assert d["chronic_issues"] and "Yüksek Riskli" in d["badges"] and not d["is_chronic_free"]
    assert d["fake_reviews_removed"] > 0
    assert d["external_ratings"] and all("text" not in e for e in d["external_ratings"])
    assert d["rating_count"] == d["review_count"] + sum(e["rating_count"] for e in d["external_ratings"])
    h = (await client.get(f"/products/{pid}/history")).json()
    assert len(h["prices"]) > 10 and h["ratings"]
    revs = (await client.get(f"/products/{pid}/experiences", params={"limit": 100})).json()
    assert revs and len(revs) == d["review_count"]  # sahte yorumlar gösterilmez


async def test_accessory_flow(client):
    cats = {c["slug"]: c for c in (await client.get("/categories")).json()}
    pc = cats["bilgisayar"]["id"]
    brands = (await client.get("/accessories/brands", params={"category_id": pc})).json()
    lenovo = next(b for b in brands if b["name"] == "Lenovo")
    models = (await client.get("/accessories/models", params={"category_id": pc, "brand_id": lenovo["id"],
                                                               "q": "15IAX9"})).json()
    types = (await client.get("/accessories/types", params={"device_id": models[0]["id"]})).json()
    assert any(t["slug"] == "ram" for t in types) and not any(t["slug"] == "kilif" for t in types)
    res = (await client.get("/accessories/compatible", params={"device_id": models[0]["id"],
                                                               "accessory_category_id": cats["ram"]["id"]})).json()
    names = [r["name"] for r in res["results"]]
    assert any("DDR5" in n and "SO-DIMM" in n for n in names)
    assert not any("DDR4" in n or "DIMM (Masaüstü)" in n for n in names)


async def test_ai_features_fallback(client):
    m = (await client.post("/ai/mission", json={"text": "Bana 1500 TL altındaki en iyi kablosuz kulaklığı bul"})).json()
    assert 1 <= len(m["top3"]) <= 3 and all(p["price"] <= 1500 for p in m["top3"])
    assert all(p["strength"] for p in m["top3"])
    sb = (await client.post("/ai/should-buy", json={"product_query": "X-Phone", "budget": 20000, "needs": "oyun"})).json()
    assert sb["verdict"] == "ALMA"
    duel = (await client.post("/ai/duel", json={"a_query": "iPhone 15", "b_query": "Galaxy S24"})).json()
    assert duel["rounds"] and duel["overall_winner"] in ("a", "b")
    iphone = (await client.get("/products", params={"q": "iPhone 15"})).json()[0]
    alts = (await client.get(f"/products/{iphone['id']}/alternatives")).json()
    assert all(a["price"] < iphone["price"] for a in alts)
    s = (await client.post("/ai/sessions", json={"mode": "general"})).json()
    msg = (await client.post(f"/ai/sessions/{s['id']}/chat", json={"text": "1500 TL altında kulaklık öner"})).json()
    assert msg["role"] == "model" and msg["text"]
    proj = (await client.post("/ai/project", json={"title": "Oyun köşesi", "description": "oyuncu mouse, çalışma masası",
                                                   "budget": 10000})).json()
    assert proj["items"] and not proj["over_budget"]
    cart = (await client.get("/cart")).json()
    assert cart["items"]


async def test_social_and_messages(client):
    pid = (await client.get("/products", params={"q": "Galaxy S24"})).json()[0]["id"]
    e = await client.post("/experiences", data={"product_id": pid, "text": "2 aydır kullanıyorum, çok memnunum", "rating": 5})
    assert e.status_code == 200
    dup = await client.post("/experiences", data={"product_id": pid, "text": "ikinci yorum denemesi", "rating": 1})
    assert dup.status_code == 409  # kullanıcı başına ürün başına tek yorum
    assert (await client.get("/explore")).json()
    assert (await client.get(f"/products/{pid}/experiences")).json()
    q = (await client.post(f"/products/{pid}/questions", json={"text": "Şarj süresi ne kadar?"})).json()
    a = (await client.post(f"/questions/{q['id']}/answers", json={"text": "Yaklaşık 1 saat"})).json()
    assert a["is_owner"]  # deneyim paylaşan kullanıcı sahip sayılır
    other = await AsyncClient(transport=ASGITransport(app=app), base_url="http://t").post(
        "/auth/register", json={"email": "b@b.co", "password": "sifre1234", "display_name": "Mehmet",
                                     "accept_terms": True, "age_confirmed": True})
    conv = (await client.post("/conversations", json={"user_id": other.json()["user"]["id"], "text": "Merhaba!"})).json()
    msgs = (await client.get(f"/conversations/{conv['id']}/messages")).json()
    assert msgs[0]["text"] == "Merhaba!"
    assert (await client.post("/profile/events", json={"kind": "purchase", "product_id": pid})).json()["ok"]


async def test_legal(client):
    for slug in ["gizlilik", "kosullar", "acik-riza", "yontem", "hesap-silme"]:
        r = await client.get(f"/legal/{slug}")
        assert r.status_code == 200 and "FiyatRadar" in r.text and "{" not in r.text.split("<body>")[1]
    bad = await client.post("/auth/register", json={"email": "c@b.co", "password": "sifre1234", "display_name": "Xyz"})
    assert bad.status_code == 400  # koşullar/yaş onayı zorunlu
    n = await client.post("/legal/notices", json={"kind": "marka_itirazi", "name": "Marka A.Ş.", "email": "hukuk@marka.com",
                                                  "target_type": "product", "target_id": 1,
                                                  "description": "Kronik sorun bilgisinin hatalı olduğunu düşünüyoruz."})
    assert n.status_code == 200
    v = await client.post("/ai/video", files={"file": ("a.mp4", b"x", "video/mp4")})
    assert v.status_code == 403  # açık rıza olmadan video yüklenemez
    assert (await client.put("/profile/consent", json={"ai_consent": True})).json()["ai_consent"]
    pid = (await client.get("/products", params={"q": "X-Phone"})).json()[0]["id"]
    d = (await client.get(f"/products/{pid}")).json()
    assert d["disclaimer"] and d["badge_basis"].get("Yüksek Riskli")


async def test_admin(client):
    from sqlalchemy import update
    from app.db import SessionLocal
    from app.models import User
    async with SessionLocal() as db:
        await db.execute(update(User).where(User.email == "a@b.co").values(is_admin=True))
        await db.commit()
    assert (await client.get("/auth/me")).json()["is_admin"]
    exp = (await client.get("/explore")).json()[0]
    await client.post("/reports", json={"target_type": "experience", "target_id": exp["id"], "reason": "Spam veya reklam"})
    reps = (await client.get("/admin/reports")).json()
    assert reps and reps[0]["text"]
    await client.post("/admin/reports/resolve", json={"target_type": "experience", "target_id": exp["id"], "hide": True})
    assert not (await client.get("/admin/reports")).json()
    notices = (await client.get("/admin/notices")).json()
    assert notices and "days_open" in notices[0]
    r = await client.post(f"/admin/notices/{notices[0]['id']}", json={"accept": False, "resolution": "Veri doğru"})
    assert r.json()["status"] == "rejected"
