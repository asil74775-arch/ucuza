import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<(Map<String, dynamic>, List<Category>)> future = load();

  Future<(Map<String, dynamic>, List<Category>)> load() async {
    final api = ref.read(apiProvider);
    final res = await Future.wait([api.get('/home'), api.get('/categories')]);
    return (
      Map<String, dynamic>.from(res[0] as Map),
      (res[1] as List).map((e) => Category.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dengi', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Mesajlar', icon: const Icon(Icons.chat_bubble_outline), onPressed: () => context.push('/messages')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => future = load()),
        child: AsyncView<(Map<String, dynamic>, List<Category>)>(
          future: future,
          onRetry: () => setState(() => future = load()),
          builder: (data) {
            final (home, cats) = data;
            final main = cats.where((c) => !c.isAccessory && c.slug != 'diger').toList();
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  readOnly: true,
                  onTap: () => context.push('/search'),
                  decoration: const InputDecoration(hintText: 'Ürün, marka veya model ara', prefixIcon: Icon(Icons.search)),
                ),
              ),
              _QuickActions(),
              SectionTitle('Kategoriler', icon: Icons.grid_view),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: main.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _CategoryBubble(main[i]),
                ),
              ),
              if ((home['for_you'] as List).isNotEmpty) ...[
                const SectionTitle('Sana Özel', icon: Icons.favorite),
                _Carousel(ProductCard.list(home['for_you'])),
              ],
              for (final s in home['showcases'] as List)
                if ((s['products'] as List).isNotEmpty) ...[
                  SectionTitle(s['badge'], icon: badgeStyle(s['badge']).icon),
                  _Carousel(ProductCard.list(s['products'])),
                ],
              for (final s in home['sections'] as List) ...[
                SectionTitle(
                  s['category']['name'],
                  action: 'Tümü',
                  onAction: () => context.push('/category/${s['category']['id']}'),
                ),
                _Carousel(ProductCard.list(s['products'])),
              ],
              const SizedBox(height: 24),
            ]);
          },
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.memory, 'Uyumlu\nAksesuar', '/accessories'),
      (Icons.videocam, 'Video ile\nKeşfet', '/ai/video'),
      (Icons.sports_mma, 'Karşılaştırma\nDüellosu', '/ai/duel'),
      (Icons.task_alt, 'Alışveriş\nGörevi', '/ai/mission'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: items
            .map((e) => Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push(e.$3),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(children: [
                        CircleAvatar(radius: 24, child: Icon(e.$1)),
                        const SizedBox(height: 6),
                        Text(e.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _CategoryBubble extends StatelessWidget {
  const _CategoryBubble(this.c);
  final Category c;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push('/category/${c.id}'),
        child: SizedBox(
          width: 72,
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(categoryIcons[c.icon] ?? Icons.category, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 6),
            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}

class _Carousel extends StatelessWidget {
  const _Carousel(this.items);
  final List<ProductCard> items;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 300,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 4),
          itemBuilder: (_, i) => ProductTile(items[i]),
        ),
      );
}
