import 'package:flutter/material.dart';

import '../../core/theme.dart';

class VerdictCard extends StatelessWidget {
  const VerdictCard(this.r, {super.key});
  final Map<String, dynamic> r;
  @override
  Widget build(BuildContext context) {
    final v = r['verdict'] as String;
    final color = {'AL': AppColors.buy, 'ALMA': AppColors.dontBuy, 'BEKLE': AppColors.wait}[v]!;
    final icon = {'AL': Icons.check_circle, 'ALMA': Icons.cancel, 'BEKLE': Icons.hourglass_top}[v]!;
    return Card(
      color: color.withValues(alpha: .1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 10),
            Text(r['verdict_label'] ?? v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
            const Spacer(),
            if (r['fit_score'] != null) Text('Uygunluk\n%${(r['fit_score'] as num).toStringAsFixed(0)}', textAlign: TextAlign.center),
          ]),
          const SizedBox(height: 8),
          Text(r['headline'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final reason in List<String>.from(r['reasons'] ?? const []))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('• '),
                Expanded(child: Text(reason)),
              ]),
            ),
          if ((r['suggestion'] ?? '').toString().isNotEmpty) ...[
            const Divider(),
            Text('Öneri: ${r['suggestion']}'),
          ],
          const SizedBox(height: 8),
          Text(r['disclaimer'] ?? 'Bu öneri otomatik üretilmiştir; kesin bir tavsiye değildir.',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}
