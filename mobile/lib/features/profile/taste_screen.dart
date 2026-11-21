import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';

/// Kişisel Zevk Profili: uygulama davranışlardan öğrenir; kullanıcı burada elle de ayarlayabilir.
class TasteScreen extends ConsumerStatefulWidget {
  const TasteScreen({super.key});
  @override
  ConsumerState<TasteScreen> createState() => _TasteScreenState();
}

class _TasteScreenState extends ConsumerState<TasteScreen> {
  Map<String, String> labels = {};
  Map<String, double> weights = {};
  double priceSensitivity = .5;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).get<Map<String, dynamic>>('/profile/taste').then((d) => setState(() {
          labels = Map<String, String>.from(d['labels']);
          weights = Map<String, dynamic>.from(d['weights']).map((k, v) => MapEntry(k, (v as num).toDouble()));
          priceSensitivity = (d['price_sensitivity'] as num).toDouble();
          loading = false;
        }));
  }

  Future<void> save() async {
    await ref.read(apiProvider).put('/profile/taste', {'weights': weights, 'price_sensitivity': priceSensitivity});
    if (mounted) toast(context, 'Zevk profilin güncellendi');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kişisel Zevk Profili'), actions: [TextButton(onPressed: save, child: const Text('Kaydet'))]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text('FiyatRadar baktığın, beğendiğin ve sepete eklediğin ürünlerden zevkini öğrenir ve arama sonuçlarını buna göre sıralar. '
                  'İstersen ilgi düzeylerini buradan elle ayarlayabilirsin.'),
              const SizedBox(height: 16),
              for (final e in labels.entries) ...[
                Text('${e.value}  (%${((weights[e.key] ?? .3) * 100).toStringAsFixed(0)})'),
                Slider(value: weights[e.key] ?? .3, onChanged: (v) => setState(() => weights[e.key] = v)),
              ],
              const Divider(),
              Text('Fiyat hassasiyeti (%${(priceSensitivity * 100).toStringAsFixed(0)})'),
              Slider(value: priceSensitivity, onChanged: (v) => setState(() => priceSensitivity = v)),
            ]),
    );
  }
}
