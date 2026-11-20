import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Yapay Zeka Destekli Alışveriş Görevi: arar, karşılaştırır, en iyi 3'ü güçlü yönüyle sunar.
class MissionScreen extends ConsumerStatefulWidget {
  const MissionScreen({super.key});
  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen> {
  final input = TextEditingController(text: 'Bana 1500 TL altındaki en iyi kablosuz kulaklığı bul');
  Map<String, dynamic>? result;
  bool busy = false;

  Future<void> run() async {
    setState(() => busy = true);
    try {
      result = await ref.read(apiProvider).post<Map<String, dynamic>>('/ai/mission', {'text': input.text});
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final top = List<Map<String, dynamic>>.from(((result?['top3']) as List? ?? const []).map((e) => Map<String, dynamic>.from(e)));
    const medals = ['🥇', '🥈', '🥉'];
    return Scaffold(
      appBar: AppBar(title: const Text('Alışveriş Görevi')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: input, maxLines: 2, decoration: const InputDecoration(labelText: 'Görevin')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : run,
          icon: const Icon(Icons.rocket_launch),
          label: Text(busy ? 'Aranıyor ve karşılaştırılıyor…' : 'Görevi başlat'),
        ),
        if (busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (result != null) ...[
          const SizedBox(height: 16),
          Text('${result!['compared']} ürün karşılaştırıldı', style: const TextStyle(color: Colors.grey)),
          if (top.isEmpty) const EmptyView('Kriterlere uyan ürün bulunamadı.'),
          for (var i = 0; i < top.length; i++)
            ProductRow(
              ProductCard.fromJson(top[i]),
              subtitle: Text('${medals[i]} ${top[i]['strength']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          if ((result!['summary'] ?? '').toString().isNotEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(result!['summary']))),
        ],
      ]),
    );
  }
}
