import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Ürün Karşılaştırma Düellosu (örn. "iPhone 15" vs "Samsung S24")
class DuelScreen extends ConsumerStatefulWidget {
  const DuelScreen({super.key, this.initialA});
  final Map<String, dynamic>? initialA;
  @override
  ConsumerState<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends ConsumerState<DuelScreen> {
  late final a = TextEditingController(text: widget.initialA?['name'] ?? 'iPhone 15');
  final b = TextEditingController(text: 'Galaxy S24');
  Map<String, dynamic>? result;
  bool busy = false;

  Future<void> fight() async {
    setState(() => busy = true);
    try {
      result = await ref.read(apiProvider).post<Map<String, dynamic>>('/ai/duel', {
        if (widget.initialA != null && a.text == widget.initialA!['name']) 'a_id': widget.initialA!['id'] else 'a_query': a.text,
        'b_query': b.text,
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Karşılaştır')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: TextField(controller: a, decoration: const InputDecoration(labelText: '1. ürün'))),
          const Padding(padding: EdgeInsets.all(8), child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900))),
          Expanded(child: TextField(controller: b, decoration: const InputDecoration(labelText: '2. ürün'))),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : fight, icon: const Icon(Icons.compare_arrows), label: const Text('Karşılaştır')),
        if (busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (result != null) ..._result(context, result!),
      ]),
    );
  }

  List<Widget> _result(BuildContext context, Map<String, dynamic> r) {
    final pa = ProductCard.fromJson(Map<String, dynamic>.from(r['a']));
    final pb = ProductCard.fromJson(Map<String, dynamic>.from(r['b']));
    final winner = r['overall_winner'] == 'a' ? pa : pb;
    return [
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: ProductTile(pa)),
        Column(children: [
          Text('${r['score']['a']} - ${r['score']['b']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const Text('skor'),
        ]),
        Expanded(child: ProductTile(pb)),
      ]),
      Card(
        color: AppColors.buy.withValues(alpha: .1),
        child: ListTile(
          leading: const Icon(Icons.emoji_events, color: Color(0xFFFFB400), size: 36),
          title: Text('Kazanan: ${winner.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      for (final round in List<Map>.from(r['rounds']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: _cell('${_fmt(round['a'])}${round['unit']}', round['winner'] == 'a', TextAlign.left)),
            Expanded(flex: 2, child: Text(round['label'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
            Expanded(child: _cell('${_fmt(round['b'])}${round['unit']}', round['winner'] == 'b', TextAlign.right)),
          ]),
        ),
      if ((r['commentary'] ?? '').toString().isNotEmpty)
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(r['commentary']))),
    ];
  }

  String _fmt(dynamic v) => v is num ? (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2)) : '$v';

  Widget _cell(String t, bool win, TextAlign align) => Text(
        (win ? '✓ ' : '') + t,
        textAlign: align,
        style: TextStyle(fontWeight: win ? FontWeight.w800 : FontWeight.normal, color: win ? AppColors.buy : null),
      );
}
