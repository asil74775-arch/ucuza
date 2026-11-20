import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';

const sortLabels = {
  'best': 'En İyi Seçim',
  'cheapest': 'En Ucuz',
  'expensive': 'En Pahalı',
  'fp': 'En İyi Fiyat/Performans',
  'rating': 'En Yüksek Puan',
  'popular': 'En Popüler',
};

/// Kategori listeleme + arama + sıralama + teknik özelliklere göre filtreleme.
/// categoryId == 0 ise tüm katalogda arama yapar.
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.categoryId, this.initialQuery});
  final int categoryId;
  final String? initialQuery;
  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  late final q = TextEditingController(text: widget.initialQuery);
  String sort = 'best';
  String? badge;
  RangeValues? price;
  final specFilters = <String, dynamic>{};
  Map<String, dynamic>? facets;
  Category? category;
  late Future<List<ProductCard>> future = load();
  Timer? debounce;

  @override
  void initState() {
    super.initState();
    if (widget.categoryId > 0) _loadMeta();
  }

  Future<void> _loadMeta() async {
    final api = ref.read(apiProvider);
    final cats = await api.get<List>('/categories');
    final f = await api.get<Map<String, dynamic>>('/categories/${widget.categoryId}/facets');
    if (!mounted) return;
    setState(() {
      category = cats.map((e) => Category.fromJson(Map<String, dynamic>.from(e))).firstWhere((c) => c.id == widget.categoryId);
      facets = f;
    });
  }

  Future<List<ProductCard>> load() async {
    final data = await ref.read(apiProvider).get<List>('/products', {
      'category_id': widget.categoryId > 0 ? widget.categoryId : null,
      'q': q.text.trim().isEmpty ? null : q.text.trim(),
      'sort': sort,
      'badge': badge,
      'min_price': price?.start,
      'max_price': price?.end,
      'specs': specFilters.isEmpty ? null : jsonEncode(specFilters),
      'limit': 60,
    });
    if (q.text.trim().isNotEmpty) track(ref, 'search', payload: {'q': q.text.trim()});
    return ProductCard.list(data);
  }

  void reload() => setState(() => future = load());

  @override
  Widget build(BuildContext context) {
    final activeFilters = specFilters.length + (price != null ? 1 : 0) + (badge != null ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: q,
          autofocus: widget.categoryId == 0 && widget.initialQuery == null,
          decoration: InputDecoration(
            hintText: category == null ? 'Tüm ürünlerde ara' : '${category!.name} içinde ara',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (_) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 400), reload);
          },
        ),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: Text(activeFilters > 0 ? 'Filtreler ($activeFilters)' : 'Filtreler'),
              onPressed: facets == null && widget.categoryId > 0 ? null : _openFilters,
            ),
            const SizedBox(width: 8),
            for (final e in sortLabels.entries) ...[
              ChoiceChip(
                label: Text(e.value),
                selected: sort == e.key,
                onSelected: (_) {
                  sort = e.key;
                  reload();
                },
              ),
              const SizedBox(width: 6),
            ],
          ]),
        ),
        Expanded(
          child: AsyncView<List<ProductCard>>(
            future: future,
            onRetry: reload,
            builder: (items) => items.isEmpty
                ? const EmptyView('Bu kriterlere uyan ürün bulunamadı.\nFiltreleri gevşetmeyi deneyin.', icon: Icons.search_off)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) => ProductRow(items[i]),
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final specs = List<Map<String, dynamic>>.from((facets?['specs'] as List?) ?? const []);
        final p = facets?['price'] as Map?;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
            Text('Filtreler', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('Güven rozeti', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(spacing: 6, children: [
              for (final b in ['En İyi Fiyat', 'En Güvenilir', 'Öğrenciler İçin İdeal', 'Kroniksiz', 'En İyi Seçim'])
                ChoiceChip(label: Text(b), selected: badge == b, onSelected: (v) => setSheet(() => badge = v ? b : null)),
            ]),
            if (p != null && (p['max'] as num) > (p['min'] as num)) ...[
              const SizedBox(height: 16),
              Text('Fiyat: ${tl((price?.start ?? p['min']))} – ${tl((price?.end ?? p['max']))}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              RangeSlider(
                min: (p['min'] as num).toDouble(),
                max: (p['max'] as num).toDouble(),
                values: price ?? RangeValues((p['min'] as num).toDouble(), (p['max'] as num).toDouble()),
                onChanged: (v) => setSheet(() => price = v),
              ),
            ],
            const Divider(height: 32),
            Text('Teknik özellikler', style: Theme.of(ctx).textTheme.titleMedium),
            for (final f in specs) _specFilter(f, setSheet),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setSheet(() {
                    specFilters.clear();
                    price = null;
                    badge = null;
                  }),
                  child: const Text('Temizle'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    reload();
                  },
                  child: const Text('Uygula'),
                ),
              ),
            ]),
          ]),
        );
      }),
    );
    setState(() {});
  }

  Widget _specFilter(Map<String, dynamic> f, StateSetter setSheet) {
    final key = f['key'] as String;
    final label = '${f['label']}${(f['unit'] ?? '').toString().isNotEmpty ? ' (${f['unit'].toString().trim()})' : ''}';
    switch (f['type']) {
      case 'number':
        final lo = (f['min'] as num).toDouble(), hi = (f['max'] as num).toDouble();
        if (hi <= lo) return const SizedBox.shrink();
        final cur = specFilters[key] as Map?;
        final values = RangeValues((cur?['min'] ?? lo).toDouble(), (cur?['max'] ?? hi).toDouble());
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Text('$label: ${values.start.toStringAsFixed(0)} – ${values.end.toStringAsFixed(0)}'),
          RangeSlider(
            min: lo,
            max: hi,
            values: values,
            onChanged: (v) => setSheet(() => specFilters[key] = {'min': v.start, 'max': v.end}),
          ),
        ]);
      case 'enum':
        final opts = List<String>.from(f['options'] ?? const []);
        final cur = List<String>.from(specFilters[key] ?? const []);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Text(label),
          Wrap(spacing: 6, children: [
            for (final o in opts)
              FilterChip(
                label: Text(o),
                selected: cur.contains(o),
                onSelected: (v) => setSheet(() {
                  v ? cur.add(o) : cur.remove(o);
                  cur.isEmpty ? specFilters.remove(key) : specFilters[key] = cur;
                }),
              ),
          ]),
        ]);
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: specFilters[key] == true,
          onChanged: (v) => setSheet(() => v ? specFilters[key] = true : specFilters.remove(key)),
        );
    }
    return const SizedBox.shrink();
  }
}
