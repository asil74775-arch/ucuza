# Avukatsız yayın için yasal kontrol listesi

> Bu liste hukuki danışmanlık değildir. Riskleri en aza indirecek şekilde tasarlanmış adımlardır.
> Uygulamanın kendisi aşağıdaki korumalarla birlikte gelir; sizin yapmanız gereken adımlar **[SİZ]** ile işaretli.

## Uygulamada hazır olan korumalar
- **Veri kaynağı:** Yalnızca sözleşmeli affiliate (ortaklık) feed'leri. Site kazıma ve kazıma tabanlı API'ler kodda yok.
- **Yorumlar:** Sadece uygulama kullanıcıları yazar; diğer sitelerden yalnızca puan ortalaması + sayısı, kaynak adıyla.
- **Etiketler:** Her rozet ve kronik sorun "kullanıcı bildirimlerine göre" diliyle ve ölçülebilir dayanağıyla gösterilir; yöntem sayfası herkese açık; her ürün sayfasında "hatalı bilgi / itiraz" butonu.
- **Yapay zeka:** Kararların altında "tavsiye değildir" uyarısı; asistan marka hakkında kesin hüküm kurmayacak şekilde yönlendirildi.
- **KVKK:** Aydınlatma metni; yurt dışına (Gemini) aktarım yalnızca **isteğe bağlı açık rıza** ile; rıza yoksa hiçbir kullanıcı içeriği gönderilmez; videolar analizden hemen sonra silinir; konum/kimlik/ödeme verisi toplanmaz.
- **Kullanıcı içeriği (5651):** Şikayet, engelleme, 3 şikayette otomatik gizleme, giriş gerektirmeyen hak ihlali formu, yönetici paneli uç noktaları.
- **Play Store:** 18+ onayı, koşulların sürümlü kabulü, uygulama içi ve web üzerinden hesap silme, herkese açık gizlilik politikası adresi.
- **Yasal metinler:** `backend/legal/` — sunucu tarafından `https://api.ucuza.com/legal/...` adreslerinde yayınlanır.

## [SİZ] Yayından önce
1. **İsim ve alan adı.** "Ucuza" Türkçede genel bir kelime ("ucuz şekilde") ve benzer isimler kullanımda (ör. Ucuzabilet.com). Bu iki sonuç doğurur:
   - Başkasının tescilli markasını ihlal etme riskine karşı **TÜRKPATENT online marka araştırmasını** yapın (ücretsiz, e-Devlet ile giriş, "ucuza" kelimesini 9, 35 ve 42. sınıflarda arayın). Birebir veya çok benzer bir tescil çıkarsa başka isim seçin.
   - `ucuza.com` alan adının boşta olup olmadığına bakın (alan adı satıcılarının "whois" sorgusu). Alınmışsa `ucuza.app` gibi bir alternatif ya da farklı isim gerekir; uygulama adını alan adınızla aynı tutun.
2. **İşletme kaydı.** Affiliate geliri vergiye tabidir. Bir **mali müşavirle** (avukattan çok daha ucuz) şahıs şirketi açın. Unvan ve adresinizi `backend/.env` içindeki `OPERATOR_NAME`, `OPERATOR_ADDRESS`, `CONTACT_EMAIL` alanlarına yazın — tüm yasal metinler otomatik güncellenir.
3. **VERBİS.** Küçük işletmelerin çoğu VERBİS kaydından muaftır. `verbis.kvkk.gov.tr` adresindeki muafiyet koşullarını kontrol edin (çalışan sayısı ve yıllık bilanço eşiği).
4. **Yapay zeka.** Google AI Studio'da faturalandırmayı açıp **ücretli katmanı** kullanın ve `GEMINI_PAID_TIER=true` yapın (az kullanımda maliyeti düşüktür). Ücretsiz katmanda Google içerikleri kendi modelleri için kullanabilir; açık rıza metni bu durumu kullanıcıya otomatik söyler, ama ücretli katman daha güvenlidir.
5. **Affiliate programları.** Yalnızca resmi ortaklık programlarına katılın, sözleşmelerini okuyun: puanların ve ürün görsellerinin uygulamada gösterilmesine izin verdiklerinden emin olun. Marka logolarını kullanmayın.
6. **Play Console'a girilecek adresler.** Gizlilik politikası: `https://api.ucuza.com/legal/gizlilik` · Hesap silme: `https://api.ucuza.com/legal/hesap-silme`.

## [SİZ] Yayından sonra (sürekli)
1. Uygulamaya kendi e-postanızla kaydolun ve sunucuda `python -m scripts.make_admin sizin@eposta.com` çalıştırın.
2. **Her gün** `GET /admin/notices` ve `GET /admin/reports` listesini kontrol edin. Hak ihlali ve itirazları **48 saat içinde** yanıtlayın (bunu koşullarda taahhüt ettik). Haklı bir itirazda içeriği gizleyin veya hatalı veriyi düzeltin. Şüphede kalırsanız içeriği gizlemek, yayında tutmaktan daha güvenlidir.
3. KVKK başvurularına (bilgi, silme talebi) **30 gün içinde** e-postayla yanıt verin.
4. Puan kriterlerini hiçbir marka lehine değiştirmeyin; ücret karşılığı sıralama veya rozet satmayın. (Satarsanız bunun "reklam" olarak açıkça etiketlenmesi gerekir.)
5. Koşulları değiştirirseniz `TERMS_VERSION` değerini artırın.

## Ne zaman mutlaka bir hukukçuya danışmalısınız?
- Bir markadan veya kurumdan **resmi ihtarname, dava veya savcılık yazısı** gelirse.
- Uygulamaya **ödeme alma**, kendi ürün satışı veya ücretli üyelik eklemek isterseniz.
- Kullanıcı sayısı büyüyüp şirket yatırım alacak hale gelirse.
Bu durumlarda tek seferlik danışmanlık genellikle yeterlidir; baroların ücretsiz adli yardım büroları da gelir durumunuza göre destek verebilir.
