# Google Play yayın kontrol listesi — BinÖlçBirAl

## 1. Teknik hazırlık
- [ ] `applicationId = com.binolcbiral.app` (mobile/android/app/build.gradle.kts) — yayından sonra değiştirilemez.
- [ ] Yükleme anahtarı oluştur:
  `keytool -genkey -v -keystore mobile/android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
  ve `mobile/android/key.properties.example` → `key.properties` (git'e eklenmez). Play App Signing'i etkinleştir.
- [ ] Uygulama ikonu (512×512) ve adaptive icon: `flutter_launcher_icons` ile `mipmap` setini üret.
- [ ] `pubspec.yaml` → `version: 1.0.0+1`; her yüklemede `+N` artmalı.
- [ ] Backend HTTPS üzerinde (`usesCleartextTraffic=false` yalnızca release'te; debug manifest yerel http'ye izin verir).
- [ ] `flutter build appbundle --release --dart-define=API_URL=https://api.binolcbiral.com`
- [ ] Hedef API seviyesi: Flutter'ın güncel `targetSdk`'si (Play'in yıllık zorunluluğunu karşılar).

## 2. Mağaza girişi (öneri metinleri)
- **Ad:** BinÖlçBirAl: Akıllı Alışveriş & Fiyat Analizi
- **Kısa açıklama (80):** Yapay zeka ile sahte yorumları ayıkla, kronik sorunları gör, en iyi ürünü seç.
- **Uzun açıklama — ana başlıklar:** Platform puanları tek ekranda · Gerçek kullanıcı yorumları · En İyi Seçim puanı · Sahte Yorum Dedektörü · Kronik Sorunlar & Kroniksiz etiketi · Fiyat ve puan geçmişi · Satın Almalı Mıyım? · Alışveriş Görevi · Proje Asistanı · Karşılaştırma Düellosu · Video ile ürün analizi · AR ile odanda gör / üzerinde dene · Uyumlu aksesuar bulucu · Keşfet & Soru-Cevap · Mesajlaşma
- **Kategori:** Alışveriş · **Ekran görüntüleri:** telefon için en az 2 (öneri 8): ana sayfa, ürün detay (kronik + rozet), sahte yorum uyarısı, düello, satın almalı mıyım kararı, AR, keşfet, aksesuar bulucu.

## 3. Politika uyumu (kodda karşılığı olanlar)
| Gereksinim | Uygulamadaki karşılık |
|---|---|
| Hesap silme (uygulama içi + web) | Profil → "Hesabımı ve verilerimi sil" → `DELETE /auth/me`. Web adresi: `https://api.binolcbiral.com/legal/hesap-silme` |
| Kullanıcı içeriği (UGC) moderasyonu | Her paylaşım/soru/cevap/mesajda "Şikayet et" ve "Engelle"; 3 şikayette otomatik gizleme; bağlantı/iletişim bilgisi filtresi; kayıtta koşulların kabulü |
| Gizlilik politikası | Sunucu tarafından `https://api.binolcbiral.com/legal/gizlilik` adresinde yayınlanır (`backend/legal/`) |
| Ödemeler | Fiziksel ürünler satıcının sitesinde alınır (affiliate). Google Play Billing gerekmez. |
| Affiliate şeffaflığı | Profil ekranında bilgilendirme; mağaza açıklamasına da ekleyin |
| İzinler | Yalnızca İnternet, Kamera, Mikrofon (video kaydı). Galeri için Photo Picker → depolama izni yok. AR/kamera `required=false`. |
| Yapay zeka üretimi içerik | AI yanıtları kullanıcıya "yapay zeka" ikonuyla belirtilir; kullanıcılar içerik şikayet edebilir (Play AI-generated content politikası). |
| Yorumlar ve puanlar | Yorumlar yalnızca BinÖlçBirAl kullanıcılarına aittir; diğer platformlardan yalnızca puan ortalaması ve sayısı, kaynak adıyla gösterilir. Sahte olasılığı yüksek kullanıcı yorumları gizlenir. |

## 4. Veri güvenliği formu (Data safety) — önerilen yanıtlar
| Veri türü | Toplanır | Paylaşılır | Amaç | Zorunlu |
|---|---|---|---|---|
| E-posta, ad | Evet | Hayır | Hesap yönetimi | Evet |
| Kullanıcı içeriği (yorum, foto, video, mesaj) | Evet | Hayır* | Uygulama işlevi | Hayır |
| Uygulama etkileşimleri (görüntüleme, sepet) | Evet | Hayır | Kişiselleştirme (Zevk Profili) | Hayır |
| Fotoğraf/video (video analizi) | Evet | Evet (Google Gemini işleyicisi) | Uygulama işlevi | Hayır |

\* Gemini, video/yorum analizi için **veri işleyici** olarak kullanılır. Aktarım şifrelidir (HTTPS); kullanıcı verilerini silme talebi desteklenir. Not: Gemini ücretsiz katmanında Google gönderilen içeriği ürün iyileştirme için kullanabilir — üretimde **ücretli katman** (Gemini API paid tier / Vertex AI) önerilir ve gizlilik politikasında belirtilmelidir.

## 5. İçerik derecelendirmesi ve hedef kitle
- IARC anketi: kullanıcılar arası iletişim **var**, kullanıcı içeriği paylaşımı **var**, satın alma bağlantıları **var**.
- Hedef yaş: 13+ (öneri 18+; mesajlaşma nedeniyle çocuk hedefli kitleden kaçının).

## 6. Yayın stratejisi
1. Dahili test (internal testing) → 2. Kapalı test (yeni kişisel geliştirici hesapları için **en az 12 test kullanıcısı / 14 gün** şartı) → 3. Üretim, kademeli dağıtım %10 → %100.
