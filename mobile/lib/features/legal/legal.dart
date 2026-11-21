import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';

/// Yasal metinler backend'de herkese açık web sayfası olarak yayınlanır (Play Store bu adresleri ister).
const legalDocs = {
  'gizlilik': 'Gizlilik Politikası ve KVKK Aydınlatma Metni',
  'kosullar': 'Kullanım Koşulları',
  'acik-riza': 'Açık Rıza Metni',
  'yontem': 'Puanlama Yöntemi',
  'hesap-silme': 'Hesap ve Veri Silme',
};

Future<void> openLegal(String slug) => launchUrl(Uri.parse('$apiUrl/legal/$slug'), mode: LaunchMode.inAppBrowserView);

/// Tıklanabilir yasal bağlantı metni
class LegalLink extends StatelessWidget {
  const LegalLink(this.slug, {super.key, this.label});
  final String slug;
  final String? label;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => openLegal(slug),
        child: Text(label ?? legalDocs[slug]!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
      );
}

const aiDisclaimer = 'Yapay zeka yanıtları bilgilendirme amaçlıdır, hata içerebilir ve satın alma tavsiyesi değildir.';
