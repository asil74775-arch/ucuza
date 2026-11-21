import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../social/explore_screen.dart' show ExperienceCard;
import 'charts.dart';
import '../legal/legal.dart';

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.id});
  final int id;
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  late Future<List<dynamic>> future = load();

  Future<List<dynamic>> load() {
    final api = ref.read(apiProvider);
    track(ref, 'view', productId: widget.id);
    return Future.wait([
      api.get('/products/${widget.id}'),
      api.get('/products/${widget.id}/history'),
      api.get('/products/${widget.id}/experiences', {'limit': 10}),
    ]);
  }

  Future<void> addToCart(Map p) async {
    await ref.read(apiProvider).post('/cart', {'product_id': p['id']});
    track(ref, 'cart', productId: p['id']);
    if (mounted) toast(context, 'Sepete eklendi');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncView<List<dynamic>>(
        future: future,
        onRetry: () => setState(() => future = load()),
        builder: (d) {
          final p = Map<String, dynamic>.from(d[0]);
          final hist = Map<String, dynamic>.from(d[1]);
          final exps = List<Map<String, dynamic>>.from((d[2] as List).map((e) => Map<String, dynamic>.from(e)));
          return Stack(children: [
            CustomScrollView(slivers: [
              SliverAppBar(
                expandedHeight: 360,
                pinned: true,
                actions: [
                  IconButton(
                    tooltip: 'Analizi yenile',
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await ref.read(apiProvider).post('/products/${p['id']}/refresh');
                      if (context.mounted) toast(context, 'Yorumlar internetten toplanıyor ve yapay zeka ile analiz ediliyor…');
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(background: _Gallery(List<String>.from(p['images'] ?? const []))),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  _Header(p),
                  _ActionGrid(p),
                  _PlatformRatings(p),
                  _ScoreBreakdown(p),
                  _OffersSection(p),
                  _SpecsSection(p),
                  _PriceSection(p, hist),
                  _RatingSection(hist),
                  _ChronicSection(p),
                  SectionTitle('Bizden Alanlar — Kullanıcı Yorumları (${p['review_count'] ?? 0})', icon: Icons.people,
                      action: 'Yorum yaz', onAction: () => context.push('/product/${p['id']}/share')),
                  _FakeWarning(p),
                  if (exps.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Henüz yorum yok. Ürünü kullandıysan ilk yorumu sen yaz!'))
                  else
                    for (final e in exps) ExperienceCard(e, compact: true),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(p['disclaimer'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Bu sayfada hatalı bilgi mi var?'),
                    subtitle: const Text('Marka, satıcı veya kullanıcı olarak itiraz edin'),
                    onTap: () => context.push('/notice', extra: {'type': 'product', 'id': p['id'], 'label': p['name']}),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('Topluluk Soru-Cevap'),
                    subtitle: const Text('Ürüne sahip olanlara sor'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/product/${p['id']}/qa'),
                  ),
                  const SizedBox(height: 100),
                ]),
              ),
            ]),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('En düşük fiyat', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(tl(p['price']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                    FilledButton.icon(onPressed: () => addToCart(p), icon: const Icon(Icons.add_shopping_cart), label: const Text('Sepete ekle')),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery(this.images);
  final List<String> images;
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const NetImage(null);
    return Stack(children: [
      PageView.builder(
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => index = i),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
              body: PhotoViewGallery.builder(
                itemCount: widget.images.length,
                pageController: PageController(initialPage: i),
                builder: (_, j) => PhotoViewGalleryPageOptions(imageProvider: NetworkImage(widget.images[j])),
              ),
            ),
          )),
          child: NetImage(widget.images[i], fit: BoxFit.contain),
        ),
      ),
      Positioned(
        bottom: 12,
        left: 0,
        right: 0,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < widget.images.length; i++)
            Container(
              margin: const EdgeInsets.all(3),
              width: i == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(color: i == index ? AppColors.brand : Colors.black26, borderRadius: BorderRadius.circular(3)),
            ),
        ]),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final badges = List<String>.from(p['badges'] ?? const []);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p['brand'] != null) Text(p['brand'], style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        Text(p['name'], style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (p['model_code'] != null) Text('Model: ${p['model_code']}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        Row(children: [
          Stars((p['rating'] ?? 0).toDouble(), size: 18, count: p['rating_count']),
          const SizedBox(width: 6),
          const Tooltip(
            message: 'Platform puanları ve Ucuza.com kullanıcı yorumlarının, puan sayısına göre ağırlıklı ortalaması',
            child: Icon(Icons.info_outline, size: 16),
          ),
          const Spacer(),
          ScorePill((p['best_choice_score'] ?? 0).toDouble()),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: badges
              .map((b) => GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(b),
                        content: Text((p['badge_basis'] ?? const {})[b] ?? ''),
                        actions: [
                          TextButton(onPressed: () => openLegal('yontem'), child: const Text('Yöntem')),
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
                        ],
                      ),
                    ),
                    child: BadgeChip(b),
                  ))
              .toList(),
        ),
        if (badges.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Rozetin dayanağını görmek için üzerine dokunun.', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        const SizedBox(height: 10),
        Text(p['description'] ?? ''),
      ]),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.help_center, 'Satın Almalı\nMıyım?', () => context.push('/ai/should-buy', extra: p)),
      (Icons.savings, 'Ucuz\nAlternatif', () => context.push('/product/${p['id']}/alternatives')),
      (Icons.sports_mma, 'Düelloya\nSok', () => context.push('/ai/duel', extra: p)),
      if (p['ar_type'] != null) (Icons.view_in_ar, 'AR ile\nGör', () => context.push('/ar', extra: p)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: actions
            .map((a) => Expanded(
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: InkWell(
                      onTap: a.$3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(children: [
                          Icon(a.$1),
                          const SizedBox(height: 4),
                          Text(a.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown(this.p);
  final Map<String, dynamic> p;
  static const labels = {
    'price': 'Fiyat',
    'reviews': 'Yorumlar',
    'features': 'Özellikler',
    'durability': 'Dayanıklılık',
    'popularity': 'Popülerlik',
    'value': 'Fiyat/Performans',
  };
  @override
  Widget build(BuildContext context) {
    final b = Map<String, dynamic>.from(p['score_breakdown'] ?? const {});
    if (b.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      const SectionTitle('Akıllı "En İyi Seçim" Puanı', icon: Icons.insights),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          for (final e in labels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 120, child: Text(e.value)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: ((b[e.key] ?? 0) as num) / 100, minHeight: 10),
                  ),
                ),
                SizedBox(width: 40, child: Text(' ${(b[e.key] ?? 0).toStringAsFixed(0)}', textAlign: TextAlign.right)),
              ]),
            ),
          Text('Kategorideki tüm ürünlerle fiyat, yorum, özellik, dayanıklılık, popülerlik ve F/P dengesi karşılaştırılarak hesaplanır.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ]);
  }
}

class _OffersSection extends StatelessWidget {
  const _OffersSection(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final offers = List<Map>.from(p['offers'] ?? const []);
    if (offers.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      const SectionTitle('Satıcılar', icon: Icons.storefront),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Ortaklık bağlantısıdır: bu bağlantılardan alışveriş yaparsanız Ucuza.com komisyon alabilir. '
            'Fiyatlar gecikmeli olabilir; güncel fiyat satıcı sitesindedir.', style: TextStyle(fontSize: 11, color: Colors.grey)),
      ),
      for (final o in offers)
        ListTile(
          leading: const Icon(Icons.store),
          title: Text(o['seller']),
          subtitle: Text(o['in_stock'] ? 'Stokta' : 'Stokta yok'),
          trailing: Text(tl(o['price']), style: const TextStyle(fontWeight: FontWeight.w800)),
          onTap: () => launchUrl(Uri.parse(o['url']), mode: LaunchMode.externalApplication),
        ),
    ]);
  }
}

class _SpecsSection extends StatelessWidget {
  const _SpecsSection(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final specs = Map<String, dynamic>.from(p['specs'] ?? const {});
    final schema = List<Map>.from(p['spec_schema'] ?? const []);
    final rows = <(String, String)>[];
    for (final f in schema) {
      final v = specs[f['key']];
      if (v == null) continue;
      rows.add((f['label'], v is bool ? (v ? 'Var' : 'Yok') : '$v${f['unit'] ?? ''}'));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      const SectionTitle('Teknik Özellikler', icon: Icons.list_alt),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Table(
          columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4)},
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                decoration: BoxDecoration(color: i.isEven ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5) : null),
                children: [
                  Padding(padding: const EdgeInsets.all(8), child: Text(rows[i].$1, style: const TextStyle(color: Colors.grey))),
                  Padding(padding: const EdgeInsets.all(8), child: Text(rows[i].$2, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
          ],
        ),
      ),
    ]);
  }
}

class _PriceSection extends StatelessWidget {
  const _PriceSection(this.p, this.hist);
  final Map<String, dynamic> p;
  final Map<String, dynamic> hist;
  @override
  Widget build(BuildContext context) {
    final s = Map<String, dynamic>.from(p['price_stats'] ?? const {});
    final trend = {'down': '↓ Düşüşte', 'up': '↑ Yükselişte', 'flat': '→ Sabit'}[s['trend']] ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Fiyat Geçmişi', icon: Icons.show_chart),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, children: [
          Chip(label: Text('90g en düşük: ${tl(s['min'])}')),
          Chip(label: Text('Ortalama: ${tl(s['avg'])}')),
          if (trend.isNotEmpty) Chip(label: Text(trend)),
        ]),
      ),
      SizedBox(
        height: 200,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
          child: HistoryChart(points: List<Map>.from(hist['prices'] ?? const []), valueKey: 'price', money: true),
        ),
      ),
    ]);
  }
}

class _RatingSection extends StatelessWidget {
  const _RatingSection(this.hist);
  final Map<String, dynamic> hist;
  @override
  Widget build(BuildContext context) {
    final pts = List<Map>.from(hist['ratings'] ?? const []);
    if (pts.length < 2) return const SizedBox.shrink();
    return Column(children: [
      const SectionTitle('Puanlama Geçmişi', icon: Icons.star_rate),
      SizedBox(
        height: 160,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
          child: HistoryChart(points: pts, valueKey: 'ai_rating', minY: 1, maxY: 5),
        ),
      ),
    ]);
  }
}

class _ChronicSection extends StatelessWidget {
  const _ChronicSection(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final chronic = List<Map>.from(p['chronic_issues'] ?? const []);
    final frequent = List<Map>.from(p['frequent_complaints'] ?? const []);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Kullanıcıların Bildirdiği Kronik Sorunlar', icon: Icons.report_problem),
      if (chronic.isEmpty)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: const Color(0xFF00A884).withValues(alpha: .1),
          child: ListTile(
            leading: const BadgeChip('Kroniksiz'),
            title: Text(p['is_chronic_free'] == true
                ? 'Zaman içinde tekrarlayan bir sorun tespit edilmedi.'
                : 'Kronik sorun tespit edilmedi (henüz yeterli yorum yok).'),
          ),
        )
      else
        for (final c in chronic)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppColors.dontBuy.withValues(alpha: .08),
            child: ListTile(
              leading: Icon(Icons.warning_amber, color: c['severity'] == 'high' ? AppColors.dontBuy : AppColors.wait),
              title: Text(c['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Kullanıcı yorumlarının %${((c['share'] as num) * 100).toStringAsFixed(0)}\'inde, '
                  '${c['months_active']} farklı ayda dile getirildi (${c['mention_count']} şikayet)'),
              trailing: Text({'high': 'Yüksek', 'medium': 'Orta', 'low': 'Düşük'}[c['severity']] ?? ''),
            ),
          ),
      if (frequent.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Zaman içinde sık dile getirilen şikayetler', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        for (final f in frequent)
          ListTile(
            dense: true,
            leading: const Icon(Icons.chat_bubble_outline, size: 18),
            title: Text(f['title']),
            trailing: Text('%${((f['share'] as num) * 100).toStringAsFixed(0)}'),
          ),
      ],
    ]);
  }
}

/// Dış platformlardan alınan YALNIZCA puan ve puan sayısı + Ucuza.com kullanıcı puanı.
class _PlatformRatings extends StatelessWidget {
  const _PlatformRatings(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final ext = List<Map>.from(p['external_ratings'] ?? const []);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Platform Puanları', icon: Icons.star_rate),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          for (final e in ext)
            ListTile(
              dense: true,
              leading: const Icon(Icons.storefront),
              title: Text(e['source']),
              trailing: Stars((e['rating'] as num).toDouble(), size: 13, count: e['rating_count']),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.verified_user),
            title: const Text('Ucuza.com kullanıcıları'),
            subtitle: const Text('Yapay zeka ile analiz edilmiş, sahte yorumlar hariç'),
            trailing: (p['review_count'] ?? 0) > 0
                ? Stars((p['ai_rating'] ?? 0).toDouble(), size: 13, count: p['review_count'])
                : const Text('Henüz yok'),
          ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text('Diğer platformlardan yalnızca puan ortalaması ve puan sayısı alınır; yorumlar Ucuza.com kullanıcılarına aittir.',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    ]);
  }
}

class _FakeWarning extends StatelessWidget {
  const _FakeWarning(this.p);
  final Map<String, dynamic> p;
  @override
  Widget build(BuildContext context) {
    final removed = p['fake_reviews_removed'] ?? 0;
    if (removed == 0) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: AppColors.wait.withValues(alpha: .12),
      child: ListTile(
        leading: const Icon(Icons.gpp_maybe, color: AppColors.wait),
        title: Text('Sahte Yorum Dedektörü $removed yorumu kaldırdı'),
        subtitle: const Text('Kopyalanmış, sponsorlu veya bot olma ihtimali yüksek yorumlar gösterilmez ve puana dahil edilmez.'),
      ),
    );
  }
}

/// Ürün kartından gelen veriyle tipli nesne gerektiğinde
ProductCard asCard(Map<String, dynamic> p) => ProductCard.fromJson(p);
