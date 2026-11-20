import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Sepet. Satın alma, affiliate bağlantısıyla satıcının sitesinde tamamlanır
/// (Google Play ödeme politikası: fiziksel ürünler için harici ödeme serbesttir).
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});
  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  late Future<Map<String, dynamic>> future = load();
  Future<Map<String, dynamic>> load() => ref.read(apiProvider).get('/cart');
  void reload() => setState(() => future = load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sepetim'), actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))]),
      body: AsyncView<Map<String, dynamic>>(
        future: future,
        onRetry: reload,
        builder: (d) {
          final items = List<Map>.from(d['items']);
          if (items.isEmpty) return const EmptyView('Sepetin boş.\nProje Asistanı ile ihtiyaç listeni otomatik oluşturabilirsin.', icon: Icons.shopping_bag_outlined);
          final groups = <String, List<Map>>{};
          for (final i in items) {
            groups.putIfAbsent(i['project_title'] ?? 'Ürünler', () => []).add(i);
          }
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.all(8), children: [
                for (final g in groups.entries) ...[
                  SectionTitle(g.key, icon: g.key == 'Ürünler' ? Icons.shopping_bag : Icons.construction),
                  for (final i in g.value)
                    ProductRow(
                      ProductCard.fromJson(Map<String, dynamic>.from(i['product'])),
                      subtitle: Row(children: [
                        if ((i['note'] ?? '').toString().isNotEmpty) Expanded(child: Text(i['note'], style: const TextStyle(fontSize: 12))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: i['quantity'] > 1
                              ? () async {
                                  await ref.read(apiProvider).patch('/cart/${i['id']}', {'quantity': i['quantity'] - 1});
                                  reload();
                                }
                              : null,
                        ),
                        Text('${i['quantity']}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () async {
                            await ref.read(apiProvider).patch('/cart/${i['id']}', {'quantity': i['quantity'] + 1});
                            reload();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref.read(apiProvider).delete('/cart/${i['id']}');
                            reload();
                          },
                        ),
                      ]),
                    ),
                ],
              ]),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: Text('Toplam: ${tl(d['total'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                  FilledButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => ListView(shrinkWrap: true, children: [
                        const Padding(padding: EdgeInsets.all(16), child: Text('Her ürün, en uygun fiyatlı satıcının sayfasında satın alınır:')),
                        for (final i in items)
                          ListTile(
                            title: Text(i['product']['name']),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: () => context.push('/product/${i['product']['id']}'),
                          ),
                      ]),
                    ),
                    child: const Text('Satın al'),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
