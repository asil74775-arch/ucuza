import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';
import 'moderation.dart';

/// Topluluk Soru-Cevap: satın almadan önce ürüne sahip olanlara sor.
class QaScreen extends ConsumerStatefulWidget {
  const QaScreen({super.key, required this.productId});
  final int productId;
  @override
  ConsumerState<QaScreen> createState() => _QaScreenState();
}

class _QaScreenState extends ConsumerState<QaScreen> {
  late Future<Map<String, dynamic>> future = load();
  final ask = TextEditingController();

  Future<Map<String, dynamic>> load() => ref.read(apiProvider).get('/products/${widget.productId}/questions');

  Future<void> submit() async {
    if (ask.text.trim().length < 5) return;
    try {
      await ref.read(apiProvider).post('/products/${widget.productId}/questions', {'text': ask.text.trim()});
      ask.clear();
      if (mounted) toast(context, 'Sorun ürün sahiplerine iletildi');
      setState(() => future = load());
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> answer(int qid) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cevapla'),
        content: TextField(controller: c, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gönder')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      try {
        await ref.read(apiProvider).post('/questions/$qid/answers', {'text': c.text.trim()});
        setState(() => future = load());
      } catch (e) {
        if (mounted) toast(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soru-Cevap'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await ref.read(apiProvider).post('/ownership/${widget.productId}');
              if (context.mounted) toast(context, 'Ürün sahibi olarak işaretlendin; yeni sorular sana bildirilecek.');
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Bu ürüne sahibim'),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            future: future,
            onRetry: () => setState(() => future = load()),
            builder: (d) {
              final qs = List<Map>.from(d['questions']);
              return ListView(padding: const EdgeInsets.all(12), children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text('${d['owner_count']} kullanıcı bu ürüne sahip'),
                    subtitle: const Text('Sorduğun soru onlara anında bildirilir.'),
                  ),
                ),
                if (qs.isEmpty) const EmptyView('İlk soruyu sen sor!'),
                for (final q in qs)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Text('S: ', style: TextStyle(fontWeight: FontWeight.w900)),
                          Expanded(child: Text(q['text'], style: const TextStyle(fontWeight: FontWeight.w600))),
                          PopupMenuButton<String>(
                            onSelected: (v) => v == 'report' ? reportContent(context, ref, 'question', q['id']) : null,
                            itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Şikayet et'))],
                          ),
                        ]),
                        Text(q['user']['name'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        for (final a in List<Map>.from(q['answers']))
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                const Text('C: ', style: TextStyle(fontWeight: FontWeight.w900)),
                                Expanded(child: Text(a['text'])),
                              ]),
                              Row(children: [
                                Text(a['user']['name'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                if (a['is_owner'] == true) ...[
                                  const SizedBox(width: 6),
                                  const Chip(visualDensity: VisualDensity.compact, label: Text('Ürün sahibi', style: TextStyle(fontSize: 10))),
                                ],
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () async {
                                    await ref.read(apiProvider).post('/answers/${a['id']}/helpful');
                                    setState(() => future = load());
                                  },
                                  icon: const Icon(Icons.thumb_up_alt_outlined, size: 14),
                                  label: Text('${a['helpful_count']}'),
                                ),
                                IconButton(
                                  tooltip: 'Mesaj gönder',
                                  icon: const Icon(Icons.chat_outlined, size: 18),
                                  onPressed: () async {
                                    final c = await ref.read(apiProvider).post<Map>('/conversations',
                                        {'user_id': a['user']['id'], 'product_id': widget.productId});
                                    if (context.mounted) context.push('/messages/${c['id']}', extra: a['user']['name']);
                                  },
                                ),
                              ]),
                            ]),
                          ),
                        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => answer(q['id']), child: const Text('Cevapla'))),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: ask, decoration: const InputDecoration(hintText: 'Ürün sahiplerine soru sor…'))),
              IconButton.filled(onPressed: submit, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
