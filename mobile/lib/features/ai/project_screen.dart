import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Proje Asistanı: projede lazım olacak eşyaları en uygun fiyatla sepete ekler.
class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({super.key});
  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  final title = TextEditingController();
  final desc = TextEditingController();
  final budget = TextEditingController();
  Map<String, dynamic>? result;
  bool busy = false;

  Future<void> run() async {
    if (title.text.trim().isEmpty) return toast(context, 'Projeye bir ad ver');
    setState(() => busy = true);
    try {
      result = await ref.read(apiProvider).post<Map<String, dynamic>>('/ai/project', {
        'title': title.text.trim(),
        'description': desc.text.trim().isEmpty ? title.text.trim() : desc.text.trim(),
        'budget': double.tryParse(budget.text.replaceAll('.', '')),
        'add_to_cart': true,
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = List<Map>.from(result?['items'] ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Proje Asistanı')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Proje', hintText: 'Örn: Ev ofisi kurmak')),
        const SizedBox(height: 10),
        TextField(
          controller: desc,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Detaylar', hintText: 'Küçük oda, günde 8 saat çalışıyorum, ikinci monitör istiyorum…'),
        ),
        const SizedBox(height: 10),
        TextField(controller: budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Toplam bütçe (TL)')),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : run,
          icon: const Icon(Icons.auto_awesome),
          label: Text(busy ? 'Liste hazırlanıyor…' : 'İhtiyaç listesini çıkar ve sepete ekle'),
        ),
        if (busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (result != null) ...[
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: Text('Toplam: ${tl(result!['total'])}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              subtitle: Text(result!['budget'] == null
                  ? '${items.length} ürün sepete eklendi'
                  : 'Bütçe: ${tl(result!['budget'])} · ${result!['over_budget'] == true ? 'Bütçe aşıldı' : 'Bütçe içinde'}'),
              trailing: FilledButton.tonal(onPressed: () => context.go('/cart'), child: const Text('Sepete git')),
            ),
          ),
          for (final it in items)
            ProductRow(
              ProductCard.fromJson(Map<String, dynamic>.from(it['product'])),
              subtitle: Text('${it['item']['name']} × ${it['item']['quantity']}${it['item']['why'] != null ? '\n${it['item']['why']}' : ''}'),
            ),
          for (final m in List<String>.from(result!['missing'] ?? const []))
            ListTile(leading: const Icon(Icons.info_outline), title: Text('Bulunamadı: $m')),
          for (final t in List<String>.from(result!['tips'] ?? const [])) ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(t)),
        ],
      ]),
    );
  }
}
