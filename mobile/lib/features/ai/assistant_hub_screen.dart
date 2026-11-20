import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AssistantHubScreen extends StatelessWidget {
  const AssistantHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.chat, 'Yapay Zeka Sohbeti', '"Şu özelliği istiyorsan şunu al" — En İyi Seçim listesiyle konuş', '/ai/chat'),
      (Icons.help_center, 'Satın Almalı Mıyım?', 'Bütçeni ve ihtiyacını söyle: Satın Al / Satın Alma / Bekle', '/ai/should-buy'),
      (Icons.task_alt, 'Alışveriş Görevi', '"1500 TL altı en iyi kablosuz kulaklığı bul" → en iyi 3 seçenek', '/ai/mission'),
      (Icons.construction, 'Proje Asistanı', 'Projen için gereken her şeyi en uygun fiyatla sepete ekler', '/ai/project'),
      (Icons.sports_mma, 'Karşılaştırma Düellosu', 'İki ürünü kategori kategori kıyasla, kazananı gör', '/ai/duel'),
      (Icons.videocam, 'Video ile Ürün Analizi', 'Videoyu yükle; ürün, yorumlar, sahte yorumlar ve karar', '/ai/video'),
      (Icons.memory, 'Uyumlu Aksesuar Bulucu', 'Cihazına uyan RAM, SSD, kılıf…', '/accessories'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Yapay Zeka Asistanı')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, i) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(child: Icon(items[i].$1)),
            title: Text(items[i].$2, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(items[i].$3),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(items[i].$4),
          ),
        ),
      ),
    );
  }
}
