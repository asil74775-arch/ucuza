"""Başlangıç kategorileri + demo katalog.

Çalıştır:  python -m scripts.seed
Kategoriler ve teknik özellik şemaları ÜRETİM için de gereklidir; demo ürünler
--no-demo ile atlanabilir (gerçek ürünler affiliate feed kaynaklarından gelir).
"""
from __future__ import annotations

import asyncio
import random
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

from sqlalchemy import select

from app.db import SessionLocal, init_models
from app.core.security import hash_password
from app.models import Brand, Category, Experience, ExternalRating, PriceHistory, Product, User
from app.services import fake_reviews, pipeline

N = lambda key, label, unit="", hib=True, w=1: {"key": key, "label": label, "unit": unit, "type": "number",  # noqa: E731
                                               "higher_is_better": hib, "filterable": True, "weight": w}
E = lambda key, label: {"key": key, "label": label, "type": "enum", "higher_is_better": None, "filterable": True}  # noqa: E731
B = lambda key, label, hib=True: {"key": key, "label": label, "type": "bool", "higher_is_better": hib, "filterable": True}  # noqa: E731

CATEGORIES = [
    dict(slug="telefon", name="Telefon", icon="smartphone", tags=["tech"], spec_schema=[
        N("ram_gb", "RAM", " GB"), N("storage_gb", "Depolama", " GB"), N("battery_mah", "Batarya", " mAh", w=1.5),
        N("camera_mp", "Ana Kamera", " MP"), N("screen_inch", "Ekran", "\""), N("refresh_hz", "Yenileme Hızı", " Hz"),
        N("weight_g", "Ağırlık", " g", hib=False, w=0.5), E("os", "İşletim Sistemi"), B("nfc", "NFC"),
        B("wireless_charging", "Kablosuz Şarj")]),
    dict(slug="bilgisayar", name="Bilgisayar", icon="laptop", tags=["tech"], spec_schema=[
        E("cpu", "İşlemci"), E("gpu", "Ekran Kartı"), N("ram_gb", "RAM", " GB", w=1.5),
        N("ram_max_gb", "Maks. RAM", " GB", w=0.5), E("ram_type", "RAM Tipi"), E("ram_form_factor", "RAM Form Faktörü"),
        N("ram_slots", "RAM Yuvası"), N("storage_gb", "SSD", " GB"), E("storage_interface", "SSD Arayüzü"),
        N("screen_inch", "Ekran", "\""), N("refresh_hz", "Yenileme Hızı", " Hz"), N("weight_kg", "Ağırlık", " kg", hib=False)]),
    dict(slug="kulaklik", name="Kulaklık", icon="headphones", tags=["tech"], spec_schema=[
        E("type", "Tip"), B("wireless", "Kablosuz"), B("anc", "Aktif Gürültü Engelleme"),
        N("battery_hours", "Pil Ömrü", " saat", w=1.5), E("bluetooth", "Bluetooth"), N("latency_ms", "Gecikme", " ms", hib=False),
        B("water_resistant", "Suya Dayanıklı")]),
    dict(slug="mobilya", name="Mobilya", icon="chair", tags=["home"], spec_schema=[
        E("material", "Malzeme"), N("width_cm", "Genişlik", " cm", hib=None), N("depth_cm", "Derinlik", " cm", hib=None),
        N("height_cm", "Yükseklik", " cm", hib=None), N("max_load_kg", "Taşıma Kapasitesi", " kg"), E("color", "Renk")]),
    dict(slug="giyim", name="Giyim & Aksesuar", icon="checkroom", tags=["fashion"], spec_schema=[
        E("material", "Malzeme"), E("color", "Renk"), E("gender", "Cinsiyet"), B("uv_protection", "UV Koruma")]),
    dict(slug="kozmetik", name="Kozmetik", icon="spa", tags=["cosmetics"], spec_schema=[
        E("skin_type", "Cilt Tipi"), N("volume_ml", "Hacim", " ml"), B("vegan", "Vegan"), B("fragrance_free", "Parfümsüz")]),
    dict(slug="oyun", name="Oyun Ekipmanları", icon="sports_esports", tags=["gaming", "tech"], spec_schema=[
        E("type", "Tip"), N("dpi", "DPI"), N("polling_hz", "Tepki Hızı", " Hz"), B("wireless", "Kablosuz"),
        B("rgb", "RGB")]),
    # --- Aksesuar kategorileri (uyumluluk platformu) ---
    dict(slug="ram", name="RAM Bellek", icon="memory", is_accessory=True, tags=["tech", "for:bilgisayar"], spec_schema=[
        N("capacity_gb", "Kapasite", " GB", w=1.5), E("ram_type", "Tip"), E("ram_form_factor", "Form Faktörü"),
        N("speed_mhz", "Hız", " MHz"), N("cl", "Gecikme (CL)", hib=False)]),
    dict(slug="ssd", name="SSD", icon="storage", is_accessory=True, tags=["tech", "for:bilgisayar"], spec_schema=[
        N("capacity_gb", "Kapasite", " GB"), E("storage_interface", "Arayüz"), N("read_mbs", "Okuma", " MB/s")]),
    dict(slug="kilif", name="Telefon Kılıfı", icon="phone_android", is_accessory=True, tags=["tech", "for:telefon"],
         spec_schema=[E("model_fit", "Uyumlu Model"), B("magsafe", "MagSafe")]),
    dict(slug="diger", name="Diğer", icon="category", tags=[], spec_schema=[]),
]


def img(text: str, n: int = 4) -> list[str]:
    return [f"https://placehold.co/800x800/png?text={quote(text)}+{i}" for i in range(1, n + 1)]


PRODUCTS = [
    # slug, brand, name, model, price, specs, tags, ar_type, quality(0-1), complaint profile
    ("telefon", "Apple", "iPhone 15 128 GB", "A3090", 52999, dict(ram_gb=6, storage_gb=128, battery_mah=3349, camera_mp=48,
     screen_inch=6.1, refresh_hz=60, weight_g=171, os="iOS", nfc=True, wireless_charging=True), ["tech", "premium"], "tabletop", .85, {"overheating": .07}),
    ("telefon", "Samsung", "Galaxy S24 256 GB", "SM-S921B", 44999, dict(ram_gb=8, storage_gb=256, battery_mah=4000,
     camera_mp=50, screen_inch=6.2, refresh_hz=120, weight_g=167, os="Android", nfc=True, wireless_charging=True), ["tech", "premium"], "tabletop", .83, {}),
    ("telefon", "Xiaomi", "Redmi Note 13 Pro 256 GB", "23117RA68G", 15999, dict(ram_gb=8, storage_gb=256, battery_mah=5100,
     camera_mp=200, screen_inch=6.67, refresh_hz=120, weight_g=187, os="Android", nfc=True, wireless_charging=False), ["tech", "budget"], "tabletop", .78, {"screen_issue": .04}),
    ("telefon", "Samsung", "Galaxy A55 128 GB", "SM-A556E", 19999, dict(ram_gb=8, storage_gb=128, battery_mah=5000,
     camera_mp=50, screen_inch=6.6, refresh_hz=120, weight_g=213, os="Android", nfc=True, wireless_charging=False), ["tech"], "tabletop", .74, {}),
    ("telefon", "Generic", "X-Phone Ultra Max", "XPU1", 8999, dict(ram_gb=12, storage_gb=512, battery_mah=6000, camera_mp=108,
     screen_inch=6.8, refresh_hz=90, weight_g=230, os="Android", nfc=False, wireless_charging=False), ["tech", "budget"], None, .35, {"battery_drain": .22, "screen_issue": .12}),
    ("bilgisayar", "Lenovo", "LOQ 15IAX9 i5-12450HX RTX 4050", "15IAX9", 32999, dict(cpu="Intel Core i5-12450HX", gpu="RTX 4050",
     ram_gb=12, ram_max_gb=32, ram_type="DDR5", ram_form_factor="SO-DIMM", ram_slots=2, ram_max_speed_mhz=4800, storage_gb=512,
     storage_interface="PCIe 4.0 NVMe", screen_inch=15.6, refresh_hz=144, weight_kg=2.38), ["tech", "gaming"], "tabletop", .8, {"overheating": .06}),
    ("bilgisayar", "Asus", "TUF Gaming F15 FX507ZC4", "FX507ZC4", 29999, dict(cpu="Intel Core i5-12500H", gpu="RTX 3050", ram_gb=8,
     ram_max_gb=32, ram_type="DDR4", ram_form_factor="SO-DIMM", ram_slots=2, ram_max_speed_mhz=3200, storage_gb=512,
     storage_interface="PCIe 3.0 NVMe", screen_inch=15.6, refresh_hz=144, weight_kg=2.2), ["tech", "gaming"], "tabletop", .72, {"hinge_break": .09, "noise": .08}),
    ("bilgisayar", "Apple", "MacBook Air 13 M3 16GB", "MXCR3", 48999, dict(cpu="Apple M3", gpu="M3 10 çekirdek", ram_gb=16,
     ram_max_gb=16, ram_type="LPDDR5", ram_form_factor="Lehimli", ram_slots=0, storage_gb=512, storage_interface="Lehimli",
     screen_inch=13.6, refresh_hz=60, weight_kg=1.24), ["tech", "premium"], "tabletop", .9, {}),
    ("kulaklik", "Xiaomi", "Redmi Buds 5 Pro", "M2317E1", 1399, dict(type="Kulak içi", wireless=True, anc=True, battery_hours=38,
     bluetooth="5.3", latency_ms=60, water_resistant=True), ["tech", "budget"], "wearable_face", .8, {}),
    ("kulaklik", "JBL", "Tune 520BT", "T520BT", 1299, dict(type="Kulak üstü", wireless=True, anc=False, battery_hours=57,
     bluetooth="5.3", latency_ms=120, water_resistant=False), ["tech", "budget"], "wearable_face", .75, {"connectivity": .05}),
    ("kulaklik", "Anker", "Soundcore Life P3i", "A3993", 1199, dict(type="Kulak içi", wireless=True, anc=True, battery_hours=36,
     bluetooth="5.2", latency_ms=90, water_resistant=True), ["tech", "budget"], "wearable_face", .72, {}),
    ("kulaklik", "Apple", "AirPods Pro 2 USB-C", "MTJV3", 8999, dict(type="Kulak içi", wireless=True, anc=True, battery_hours=30,
     bluetooth="5.3", latency_ms=50, water_resistant=True), ["tech", "premium"], "wearable_face", .88, {}),
    ("kulaklik", "Sony", "WH-1000XM5", "WH1000XM5", 11999, dict(type="Kulak üstü", wireless=True, anc=True, battery_hours=30,
     bluetooth="5.2", latency_ms=80, water_resistant=False), ["tech", "premium"], "wearable_face", .86, {"hinge_break": .06}),
    ("mobilya", "Vivense", "Nordic 3'lü Kanepe", "NRD3", 18999, dict(material="Kumaş", width_cm=210, depth_cm=90, height_cm=85,
     max_load_kg=300, color="Gri"), ["home"], "furniture", .78, {}),
    ("mobilya", "IKEA", "MALM Çalışma Masası", "MALM-140", 4499, dict(material="Sunta", width_cm=140, depth_cm=65, height_cm=73,
     max_load_kg=50, color="Beyaz"), ["home", "budget"], "furniture", .76, {}),
    ("mobilya", "Koçtaş", "Ergonomik Ofis Koltuğu", "ERG-01", 3299, dict(material="File", width_cm=65, depth_cm=60, height_cm=120,
     max_load_kg=120, color="Siyah"), ["home", "budget"], "furniture", .6, {"hinge_break": .1}),
    ("giyim", "Ray-Ban", "Aviator Classic Güneş Gözlüğü", "RB3025", 5999, dict(material="Metal", color="Altın", gender="Unisex",
     uv_protection=True), ["fashion", "premium"], "wearable_face", .85, {}),
    ("giyim", "Mavi", "Oversize Basic Tişört", "M0610", 499, dict(material="Pamuk", color="Siyah", gender="Unisex",
     uv_protection=False), ["fashion", "budget"], "wearable_body", .74, {}),
    ("kozmetik", "La Roche-Posay", "Effaclar Duo+ 40 ml", "LRP-ED", 749, dict(skin_type="Yağlı", volume_ml=40, vegan=False,
     fragrance_free=True), ["cosmetics"], None, .82, {}),
    ("kozmetik", "CeraVe", "Nemlendirici Krem 340 g", "CV-MC", 589, dict(skin_type="Kuru", volume_ml=340, vegan=False,
     fragrance_free=True), ["cosmetics", "budget"], None, .84, {}),
    ("oyun", "Logitech", "G Pro X Superlight 2", "910-006630", 5499, dict(type="Mouse", dpi=32000, polling_hz=8000, wireless=True,
     rgb=False), ["gaming", "premium"], "tabletop", .88, {}),
    ("oyun", "Rampage", "SMX-R50 Oyuncu Mouse", "SMXR50", 349, dict(type="Mouse", dpi=7200, polling_hz=1000, wireless=False,
     rgb=True), ["gaming", "budget"], "tabletop", .6, {"connectivity": .1}),
    # RAM aksesuarları (LOQ 15IAX9: DDR5 SO-DIMM -> uyumlu; DDR4 -> uyumsuz)
    ("ram", "Kingston", "FURY Impact 16GB DDR5 5600MHz SO-DIMM", "KF556S40IB-16", 1899, dict(capacity_gb=16, ram_type="DDR5",
     ram_form_factor="SO-DIMM", speed_mhz=5600, cl=40, compat={"ram_type": "DDR5", "ram_form_factor": "SO-DIMM",
     "capacity_gb": {"lte_device": "ram_max_gb"}, "speed_mhz": {"lte_device": "ram_max_speed_mhz"}}, compat_soft=["speed_mhz ≤ ram_max_speed_mhz"]), ["tech"], None, .85, {}),
    ("ram", "Crucial", "16GB DDR5 4800MHz SO-DIMM", "CT16G48C40S5", 1599, dict(capacity_gb=16, ram_type="DDR5",
     ram_form_factor="SO-DIMM", speed_mhz=4800, cl=40, compat={"ram_type": "DDR5", "ram_form_factor": "SO-DIMM",
     "capacity_gb": {"lte_device": "ram_max_gb"}, "speed_mhz": {"lte_device": "ram_max_speed_mhz"}}, compat_soft=["speed_mhz ≤ ram_max_speed_mhz"]), ["tech", "budget"], None, .82, {}),
    ("ram", "Samsung", "8GB DDR5 4800MHz SO-DIMM", "M425R1GB4BB0", 899, dict(capacity_gb=8, ram_type="DDR5",
     ram_form_factor="SO-DIMM", speed_mhz=4800, cl=40, compat={"ram_type": "DDR5", "ram_form_factor": "SO-DIMM",
     "capacity_gb": {"lte_device": "ram_max_gb"}}), ["tech", "budget"], None, .8, {}),
    ("ram", "Kingston", "FURY Impact 16GB DDR4 3200MHz SO-DIMM", "KF432S20IB-16", 1199, dict(capacity_gb=16, ram_type="DDR4",
     ram_form_factor="SO-DIMM", speed_mhz=3200, cl=20, compat={"ram_type": "DDR4", "ram_form_factor": "SO-DIMM",
     "capacity_gb": {"lte_device": "ram_max_gb"}}), ["tech"], None, .84, {}),
    ("ram", "Corsair", "Vengeance 32GB DDR5 6000MHz DIMM (Masaüstü)", "CMK32GX5M2B6000", 3999, dict(capacity_gb=32,
     ram_type="DDR5", ram_form_factor="DIMM", speed_mhz=6000, cl=36, compat={"ram_type": "DDR5", "ram_form_factor": "DIMM"}), ["tech", "gaming"], None, .86, {}),
    ("ssd", "Samsung", "990 EVO 1TB NVMe", "MZ-V9E1T0", 2899, dict(capacity_gb=1000, storage_interface="PCIe 4.0 NVMe",
     read_mbs=5000, compat={"storage_interface": {"in": ["PCIe 4.0 NVMe", "PCIe 3.0 NVMe"]}}), ["tech"], None, .85, {}),
]

POS_TEXTS = [
    "Fiyatına göre performansı gerçekten çok iyi, iki aydır sorunsuz kullanıyorum.",
    "Kargo hızlıydı, ürün açıklamadaki gibi. Malzeme kalitesi beklediğimden iyi.",
    "Günlük kullanımda hiçbir sorun yaşamadım, pil ömrü de gayet yeterli.",
    "Önceki modelime göre ciddi fark var, tavsiye ederim.",
    "Ses/görüntü kalitesi çok tatmin edici, ailemde de aynısını aldık.",
    "Biraz pahalı ama kalitesi hissediliyor, pişman değilim.",
]
NEU_TEXTS = ["İdare eder, fiyatı biraz daha düşük olabilirdi.", "Beklentimi kısmen karşıladı, kutu içeriği zayıf."]
COMPLAINTS = {
    "overheating": ("Aşırı ısınma", "Oyun oynarken çok ısınıyor, fan sesi de artıyor."),
    "battery_drain": ("Pil/batarya çabuk bitiyor", "Pil çok çabuk bitiyor, yarım günü zor çıkarıyor."),
    "screen_issue": ("Ekran sorunu", "Birkaç ay sonra ekranda yeşil çizgi oluştu, servise gönderdim."),
    "hinge_break": ("Menteşe/mekanizma kırılması", "Menteşe 6. ayda kırıldı, plastik aksam zayıf."),
    "noise": ("Fan/ses gürültüsü", "Fan sesi çok yüksek, sessiz ortamda rahatsız ediyor."),
    "connectivity": ("Bağlantı kopması", "Bluetooth bağlantısı sürekli kopuyor, sinir bozucu."),
}
FAKE_TEXTS = [
    "Harika ürün!!!!! Herkese tavsiye ederim!!!!!",
    "Bu ürün bana marka tarafından hediye olarak gönderildi, kesinlikle mükemmel, indirim kodu ile alabilirsiniz.",
    "Çok güzel süper",
]


async def seed(demo: bool = True) -> None:
    await init_models()
    rnd = random.Random(42)
    async with SessionLocal() as db:
        cats = {}
        for c in CATEGORIES:
            row = await db.scalar(select(Category).where(Category.slug == c["slug"]))
            if not row:
                row = Category(**c)
                db.add(row)
            else:
                row.spec_schema, row.tags = c["spec_schema"], c["tags"]
            cats[c["slug"]] = row
        await db.commit()
        if not demo or await db.scalar(select(Product.id).limit(1)):
            print("Kategoriler hazır.", "Demo ürünler zaten var." if demo else "")
            return

        now = datetime.now(timezone.utc)
        # Demo kullanıcılar (yorumlar yalnızca Ucuza.com kullanıcılarından gelir)
        pw = hash_password("demo-kullanici-sifre")
        users = []
        for i in range(90):
            u = User(email=f"demo{i}@ucuza.local", password_hash=pw, display_name=f"Demo Kullanıcı {i + 1}")
            db.add(u)
            users.append(u)
        await db.flush()

        brands: dict[str, Brand] = {}
        platforms = ["Trendyol", "Hepsiburada", "Amazon TR", "N11"]
        for slug, brand, name, model, price, specs, tags, ar, quality, cprof in PRODUCTS:
            if brand not in brands:
                brands[brand] = Brand(name=brand)
                db.add(brands[brand])
                await db.flush()
            p = Product(category_id=cats[slug].id, brand_id=brands[brand].id, name=f"{brand} {name}", model_code=model,
                        description=f"{brand} {name} — teknik özellikler, platform puanları ve Ucuza.com kullanıcı yorumları.",
                        specs=specs, images=img(f"{brand} {model}"), tags=tags, current_price=price, ar_type=ar,
                        ar_model_url=(f"https://modelviewer.dev/shared-assets/models/"
                                      f"{'Chair' if ar == 'furniture' else 'Astronaut'}.glb") if ar else None,
                        tryon_asset_url=f"https://placehold.co/600x200/png?text={quote(model)}" if ar and ar.startswith("wearable") else None,
                        source="seed")
            db.add(p)
            await db.flush()
            # 12 aylık fiyat geçmişi
            for d in range(360, -1, -15):
                drift = 1 + 0.12 * (d / 360) + rnd.uniform(-0.04, 0.04)
                db.add(PriceHistory(product_id=p.id, price=round(price * drift, -1), recorded_at=now - timedelta(days=d)))
            # Dış platform puanları: YALNIZCA ortalama + puan sayısı
            for plat in rnd.sample(platforms, 2):
                db.add(ExternalRating(product_id=p.id, source=plat,
                                      rating=round(min(5, max(1, 1 + 4 * quality + rnd.uniform(-.3, .3))), 1),
                                      rating_count=rnd.randint(50, 5000)))
            # Ucuza.com kullanıcı yorumları (kullanıcı başına tek yorum)
            pool = rnd.sample(users, len(users))
            n = rnd.randint(25, 60)
            for i in range(n):
                posted = now - timedelta(days=rnd.randint(1, 360))
                r = rnd.random()
                text, stars, comp = None, None, []
                for key, share in cprof.items():
                    if r < share:
                        text, stars = COMPLAINTS[key][1], rnd.choice([1, 2, 2, 3])
                        comp = [{"key": key, "label": COMPLAINTS[key][0]}]
                        break
                    r -= share
                if text is None:
                    if rnd.random() < quality:
                        text, stars = rnd.choice(POS_TEXTS), rnd.choice([4, 5, 5])
                    else:
                        text, stars = rnd.choice(NEU_TEXTS), rnd.choice([2, 3, 3])
                db.add(Experience(user_id=pool[i].id, product_id=p.id, text=text, rating=stars, complaints=comp,
                                  created_at=posted, content_hash=fake_reviews.content_hash(text)))
            # Sahte yorum denemeleri (aynı gün, kopya/sponsorlu metin) -> dedektör gizlemeli
            fake_n = 2 if quality > .5 else 10
            for j in range(fake_n):
                t = rnd.choice(FAKE_TEXTS)
                db.add(Experience(user_id=pool[n + j].id, product_id=p.id, text=t, rating=5,
                                  created_at=now - timedelta(days=3), content_hash=fake_reviews.content_hash(t)))
        await db.commit()

        products = (await db.scalars(select(Product))).unique().all()
        for p in products:
            await pipeline.analyze_reviews(db, p.id)
        for c in cats.values():
            await pipeline.rescore_category(db, c.id)
        print(f"{len(products)} demo ürün eklendi ve analiz edildi.")


if __name__ == "__main__":
    asyncio.run(seed(demo="--no-demo" not in sys.argv))
