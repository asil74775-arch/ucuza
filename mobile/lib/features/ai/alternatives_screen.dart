import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Alternatif Ürün Bulucu: benzer özellikli, daha uygun fiyatlı ürünler.
class AlternativesScreen extends ConsumerWidget {
  const AlternativesScreen({super.key, required this.productId});
  final int productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daha Uygun Alternatifler')),
      body: AsyncView<List>(
        future: ref.read(apiProvider).get<List>('/products/$productId/alternatives'),
        builder: (list) => list.isEmpty
            ? const EmptyView('Benzer özelliklerde daha uygun bir ürün bulunamadı. Bu ürün zaten iyi bir fiyatta olabilir.', icon: Icons.thumb_up)
            : ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final a in list)
                    ProductRow(
                      ProductCard.fromJson(Map<String, dynamic>.from(a)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${tl(a['saving'])} tasarruf (%${a['saving_pct']}) · Benzerlik %${a['similarity']}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                        for (final d in List<String>.from(a['differences'] ?? const [])) Text(d, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                ],
              ),
      ),
    );
  }
}
