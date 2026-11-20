# Kıyaslio

**Doğru ürünü, doğru fiyata.** Yapay zeka destekli alışveriş ve ürün analiz uygulaması.

- **Mobil:** Flutter (Android + iOS), Riverpod, go_router, Dio
- **Backend:** Python FastAPI, SQLAlchemy 2 (async), PostgreSQL, Redis (WebSocket ölçekleme)
- **Yapay zeka:** Google Gemini (`gemini-2.5-flash`, ücretsiz katmanı var); anahtar yoksa kural tabanlı yedek motor
- **Veri:** Resmi API ve affiliate kaynakları (Affiliate JSON feed, SerpAPI Google Shopping, YouTube Data API)

> İsim notu: "Kıyaslio" = *kıyasla* + *-io*. Yayınlamadan önce TÜRKPATENT'te (marka sınıfı 9, 35, 42) ve Play Store'da isim çakışması kontrolü yapın, `kiyaslio.com` alan adını alın.

---

## 1. Özellik → Kod haritası

| İstenen özellik | Backend | Mobil ekran |
|---|---|---|
| Ana sayfada kategoriler halinde ürünler | `GET /home` (`routers/catalog.py`) | `features/home/home_screen.dart` |
| En ucuz / en pahalı / en iyi F/P / teknik özelliğe göre arama-filtre | `GET /products?sort=&specs=`, `GET /categories/{id}/facets` | `features/catalog/category_screen.dart` (filtre paneli kategori şemasından otomatik oluşur) |
| Detaylı bilgi, özellikler, fotoğraflar | `GET /products/{id}` | `features/product/product_screen.dart` (tam ekran yakınlaştırmalı galeri) |
| Aksesuar uyumluluk platformu (PC → Lenovo → LOQ 15IAX9 → RAM) | `/accessories/brands|models|types|compatible`, kural motoru `services/matching.py::check_compat` | `features/accessories/accessory_finder_screen.dart` |
| Fiyat geçmişi, puan geçmişi, sık şikayetler | `GET /products/{id}/history`, `PriceHistory`, `RatingHistory`, `ChronicIssue` | `product/charts.dart` |
| Kronik Sorunlar / "Kroniksiz" etiketi | `services/chronic.py` (≥%5 pay ve ≥3 farklı ay = kronik) | Ürün sayfası "Kronik Sorunlar" |
| Güven rozetleri (En İyi Fiyat, En Güvenilir, Öğrenciler İçin İdeal, Yüksek Riskli, Popüler Ama Aşırı Pahalı) | `services/scoring.py::assign_badges` | `core/widgets.dart::BadgeChip` |
| İnternetten yorum toplama + AI yıldızlama | `services/pipeline.py::ingest_reviews/analyze_reviews`, `services/sources/*` | Ürün sayfası "İnternetten Toplanan Yorumlar" |
| Akıllı "En İyi Seçim" puanı ve sıralama | `services/scoring.py::score_category` (fiyat, yorum, özellik, dayanıklılık, popülerlik, F/P) | Puan dökümü çubukları |
| AI sohbetin bu listeyi kullanması | `services/assistant.py` (Gemini function calling → `search_products`, `get_product`…) | `features/ai/chat_screen.dart` |
| Sahte Yorum Dedektörü (uyar + kaldır) | `services/fake_reviews.py` (kopya, sponsor, yığılma, aynı hesap + Gemini) | Uyarı kartı + şüpheli etiketleri; ≥0.70 olasılık gizlenir |
| "Satın Almalı Mıyım?" (Al / Alma / Bekle) | `POST /ai/should-buy`, `catalog.buy_signals` + Gemini | `features/ai/should_buy_screen.dart` |
| Alışveriş Görevi ("1500 TL altı en iyi kablosuz kulaklık" → en iyi 3) | `POST /ai/mission` | `features/ai/mission_screen.dart` |
| Proje Asistanı (gereken eşyaları en uygun fiyatla sepete ekler) | `POST /ai/project` | `features/ai/project_screen.dart` |
| Alternatif Ürün Bulucu | `GET /products/{id}/alternatives` (özellik vektörü kosinüs benzerliği) | `features/ai/alternatives_screen.dart` |
| Karşılaştırma Düellosu | `POST /ai/duel` | `features/ai/duel_screen.dart` |
| Kişisel Zevk Profili | `TasteProfile`, `POST /profile/events`, `matching.personalize` | Onboarding + `features/profile/taste_screen.dart` |
| Video ile ürün keşfi, yoksa internetten bulup ekleme, "almaya değer mi" | `POST /ai/video` → `services/video.py` | `features/video/video_screen.dart` |
| AR önizleme (oda / üzerinde) | `Product.ar_type`, `ar_model_url` (.glb), `tryon_asset_url` (.png) | `features/ar/ar_screen.dart` (ARCore Scene Viewer), `ar/tryon_screen.dart` (kamera + ML Kit yüz tespiti) |
| Gerçek Kullanıcı Deneyimi (Keşfet + Bizden Alanlar) | `/experiences`, `/explore`, `/products/{id}/experiences` | `features/social/explore_screen.dart`, `create_experience_screen.dart` |
| Topluluk Soru-Cevap (sahiplere sor) | `/products/{id}/questions`, `/questions/{id}/answers`, sahiplere anlık bildirim | `features/social/qa_screen.dart` |
| Kullanıcılar arası yazışma | `/conversations`, WebSocket `/ws` (Redis pub/sub ile ölçeklenir) | `features/messages/*` |
| Play Store gereksinimleri | Hesap silme `DELETE /auth/me`, şikayet `/reports`, engelleme `/blocks` | Profil → Hesabımı sil, içerik menüleri |

## 2. Mimari

```
Flutter uygulaması ──HTTPS/JSON──▶ FastAPI ──▶ PostgreSQL (katalog, yorumlar, geçmişler, sosyal)
        │                            │  └────▶ Redis (WebSocket pub/sub)
        └──── WSS (mesajlar) ────────┤
                                     ├──▶ Gemini API (yorum analizi, sohbet+araçlar, video)
                                     └──▶ Kaynak adaptörleri (affiliate feed, SerpAPI, YouTube)
refresher servisi (günlük) ─▶ fiyat kaydı → yorum toplama → AI analiz → kronik tespit → puan/rozet
```

**Analiz boru hattı** (`services/pipeline.py`):
1. `ingest_reviews` — etkin kaynaklardan yeni yorumlar (içerik hash'i ile tekilleştirme)
2. `analyze_reviews` — kural tabanlı sahte sinyal + Gemini toplu analiz (AI yıldız, duygu, şikayet anahtarları, sahte olasılığı) → gizleme → kronik sorun tespiti → `RatingHistory`
3. `rescore_category` — kategori içi göreli En İyi Seçim / F/P puanı + rozetler

**Yapay zeka güvenliği:** Asistan ürün/fiyat **uyduramaz**; tüm öneriler Gemini fonksiyon çağrılarıyla veritabanından gelir. "Satın Alma" kararını tetikleyen kurallar (bütçe aşımı, ciddi kronik sorun, yüksek risk) modelin "Al" demesiyle ezilemez.

## 3. Kurulum

### Backend
```bash
cd backend
cp .env.example .env          # GEMINI_API_KEY'i https://aistudio.google.com/apikey adresinden alın
pip install -r requirements.txt
python -m scripts.seed        # kategoriler + demo ürünler (yalnız kategoriler: --no-demo)
uvicorn app.main:app --reload
python -m pytest -q           # 10 test
```
API dokümanı: `http://localhost:8000/docs`

Docker ile (PostgreSQL + Redis + API + günlük yenileyici):
```bash
cp backend/.env.example backend/.env && docker compose up -d --build
```

### Mobil
```bash
cd mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000      # Android emülatör
flutter test && flutter analyze
```

### Veri kaynaklarını etkinleştirme
| Değişken | Kaynak | Not |
|---|---|---|
| `AFFILIATE_FEED_URLS` | Pazar yeri/affiliate ağ ürün feed'leri (JSON) | Fiyat, ürün, affiliate bağlantısı |
| `SERPAPI_KEY` | Google Shopping + ürün yorumları | Ücretli, lisanslı arama API'si |
| `YOUTUBE_API_KEY` | İnceleme videosu yorumları | Ücretsiz kota (Google Cloud) |

Yeni bir pazar yeri eklemek için `services/sources/base.py::SourceAdapter` alt sınıfı yazıp `REGISTRY`'ye ekleyin.

## 4. Yayın
Ayrıntılı kontrol listesi: [`docs/PLAY_STORE.md`](docs/PLAY_STORE.md) · Gizlilik politikası taslağı: [`docs/GIZLILIK_POLITIKASI.md`](docs/GIZLILIK_POLITIKASI.md)

```bash
flutter build appbundle --release --dart-define=API_URL=https://api.kiyaslio.com
# çıktı: build/app/outputs/bundle/release/app-release.aab
```
