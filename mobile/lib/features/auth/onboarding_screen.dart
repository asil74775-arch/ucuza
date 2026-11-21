import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Kişisel Zevk Profili'nin ilk tohumu: kullanıcı ilgi alanlarını seçer.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const options = {
    'budget': ('Uygun fiyatlı ürünler', Icons.savings),
    'premium': ('Premium ürünler', Icons.diamond),
    'gaming': ('Oyun ekipmanları', Icons.sports_esports),
    'cosmetics': ('Kozmetik', Icons.spa),
    'tech': ('Teknoloji', Icons.devices),
    'home': ('Ev & Yaşam', Icons.chair),
    'fashion': ('Moda', Icons.checkroom),
    'sports': ('Spor & Outdoor', Icons.directions_run),
  };
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.compare_arrows, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text('BinÖlçBirAl', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 24),
            Text('Bin ölç, bir al.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Yapay zeka yorumları tarar, sahte yorumları ayıklar, kronik sorunları bulur ve sana en iyi seçimi söyler. '
                'Önce seni tanıyalım — nelerle ilgilenirsin?'),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 2.6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: options.entries.map((e) {
                  final on = selected.contains(e.key);
                  return FilterChip(
                    selected: on,
                    showCheckmark: false,
                    avatar: Icon(e.value.$2, size: 18),
                    label: Text(e.value.$1, overflow: TextOverflow.ellipsis),
                    onSelected: (v) => setState(() => v ? selected.add(e.key) : selected.remove(e.key)),
                  );
                }).toList(),
              ),
            ),
            FilledButton(
              onPressed: () => context.go('/login', extra: selected.toList()),
              child: Text(selected.isEmpty ? 'Atla ve devam et' : 'Devam et (${selected.length})'),
            ),
          ]),
        ),
      ),
    );
  }
}
