import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import 'verdict_card.dart';

/// "Satın Almalı Mıyım?" asistanı — bütçe + ihtiyaçlar → Satın Al / Satın Alma / Bekle
class ShouldBuyScreen extends ConsumerStatefulWidget {
  const ShouldBuyScreen({super.key, this.product});
  final Map<String, dynamic>? product;
  @override
  ConsumerState<ShouldBuyScreen> createState() => _ShouldBuyScreenState();
}

class _ShouldBuyScreenState extends ConsumerState<ShouldBuyScreen> {
  late final query = TextEditingController(text: widget.product?['name']);
  final budget = TextEditingController();
  final needs = TextEditingController();
  Map<String, dynamic>? result;
  bool busy = false;

  Future<void> ask() async {
    if (query.text.trim().isEmpty) return toast(context, 'Hangi ürünü düşündüğünü yaz');
    setState(() => busy = true);
    try {
      result = await ref.read(apiProvider).post<Map<String, dynamic>>('/ai/should-buy', {
        if (widget.product != null && query.text == widget.product!['name']) 'product_id': widget.product!['id'] else 'product_query': query.text.trim(),
        'budget': double.tryParse(budget.text.replaceAll('.', '').replaceAll(',', '.')),
        'needs': needs.text.trim(),
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final alts = List<Map<String, dynamic>>.from(
        ((result?['signals']?['alternatives']) as List? ?? const []).map((e) => Map<String, dynamic>.from(e)));
    return Scaffold(
      appBar: AppBar(title: const Text('Satın Almalı Mıyım?')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: query, decoration: const InputDecoration(labelText: 'Ürün', prefixIcon: Icon(Icons.shopping_bag))),
        const SizedBox(height: 10),
        TextField(
          controller: budget,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bütçen (TL)', prefixIcon: Icon(Icons.account_balance_wallet)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: needs,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'İhtiyaçların', hintText: 'Örn: Üniversite için, hafif olsun, oyun da oynarım'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : ask,
          icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
          label: const Text('Yapay zekaya sor'),
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          ProductRow(ProductCard.fromJson(Map<String, dynamic>.from(result!['product']))),
          VerdictCard(result!),
          if (alts.isNotEmpty) ...[
            const SectionTitle('Daha uygun alternatifler', icon: Icons.savings),
            for (final a in alts)
              ProductRow(ProductCard.fromJson(a), subtitle: Text('%${a['saving_pct']} daha ucuz · benzerlik %${a['similarity']}')),
          ],
        ],
      ]),
    );
  }
}
