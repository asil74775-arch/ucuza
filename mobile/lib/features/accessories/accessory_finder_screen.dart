import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Kategori -> Marka -> Model -> Aksesuar tipi -> uyumlu aksesuarlar
/// Örn: Bilgisayar -> Lenovo -> LOQ 15IAX9 -> RAM
class AccessoryFinderScreen extends ConsumerStatefulWidget {
  const AccessoryFinderScreen({super.key});
  @override
  ConsumerState<AccessoryFinderScreen> createState() => _AccessoryFinderScreenState();
}

class _AccessoryFinderScreenState extends ConsumerState<AccessoryFinderScreen> {
  List<Category> cats = [];
  List<Map> brands = [], models = [], types = [];
  Category? cat;
  Map? brand, model, type;
  Map<String, dynamic>? result;
  bool loading = false;
  String sort = 'best';

  Api get api => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    api.get<List>('/categories').then((l) => setState(() => cats = l
        .map((e) => Category.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => !c.isAccessory && c.slug != 'diger')
        .toList()));
  }

  Future<void> pickCat(Category? c) async {
    setState(() {
      cat = c;
      brand = model = type = null;
      brands = models = types = [];
      result = null;
    });
    if (c != null) brands = List<Map>.from(await api.get('/accessories/brands', {'category_id': c.id}));
    setState(() {});
  }

  Future<void> pickBrand(Map? b) async {
    setState(() {
      brand = b;
      model = type = null;
      models = types = [];
      result = null;
    });
    if (b != null) models = List<Map>.from(await api.get('/accessories/models', {'category_id': cat!.id, 'brand_id': b['id']}));
    setState(() {});
  }

  Future<void> pickModel(Map? m) async {
    setState(() {
      model = m;
      type = null;
      types = [];
      result = null;
    });
    if (m != null) types = List<Map>.from(await api.get('/accessories/types', {'device_id': m['id']}));
    setState(() {});
  }

  Future<void> search() async {
    if (model == null || type == null) return;
    setState(() => loading = true);
    try {
      result = await api.get<Map<String, dynamic>>(
          '/accessories/compatible', {'device_id': model!['id'], 'accessory_category_id': type!['id'], 'sort': sort});
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    setState(() => loading = false);
  }

  Widget _dropdown<T>(String label, T? value, List<T> items, String Function(T) text, void Function(T?) onChanged, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label-$value-${items.length}'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(text(e), overflow: TextOverflow.ellipsis))).toList(),
        onChanged: items.isEmpty ? null : onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = List<Map<String, dynamic>>.from(
        (result?['results'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)));
    return Scaffold(
      appBar: AppBar(title: const Text('Uyumlu Aksesuar Bul')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _dropdown<Category>('1. Kategori', cat, cats, (c) => c.name, pickCat, Icons.category),
        _dropdown<Map>('2. Marka', brand, brands, (b) => b['name'], pickBrand, Icons.business),
        _dropdown<Map>('3. Model', model, models, (m) => '${m['name']} ${m['model_code'] ?? ''}', pickModel, Icons.devices),
        _dropdown<Map>('4. Aksesuar', type, types, (t) => t['name'], (t) {
          setState(() => type = t);
          search();
        }, Icons.extension),
        if (model != null && type != null)
          Wrap(spacing: 6, children: [
            for (final s in {'best': 'En İyi Seçim', 'cheapest': 'En Ucuz', 'fp': 'En İyi F/P', 'expensive': 'En Pahalı'}.entries)
              ChoiceChip(
                label: Text(s.value),
                selected: sort == s.key,
                onSelected: (_) {
                  sort = s.key;
                  search();
                },
              ),
          ]),
        if (loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (result != null && !loading) ...[
          const SizedBox(height: 8),
          Text('${result!['device']['name']} ile uyumlu ${results.length} ${type!['name']}',
              style: Theme.of(context).textTheme.titleMedium),
          if (results.isEmpty) const EmptyView('Uyumlu aksesuar bulunamadı.'),
          for (final r in results)
            ProductRow(
              ProductCard.fromJson(r),
              subtitle: Row(children: [
                Icon(r['compat'] == 'full' ? Icons.check_circle : Icons.info,
                    size: 16, color: r['compat'] == 'full' ? Colors.green : Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r['compat'] == 'full' ? 'Tam uyumlu' : 'Kısmi uyumlu: ${List.from(r['compat_notes']).join(', ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
