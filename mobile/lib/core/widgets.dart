import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'theme.dart';

final _tl = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
String tl(num? v) => v == null ? '-' : _tl.format(v);

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.radius = 0});
  final String? url;
  final BoxFit fit;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final child = url == null
        ? Container(color: Colors.black12, child: const Icon(Icons.image_not_supported_outlined))
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => Container(color: Colors.black12, child: const Icon(Icons.broken_image)),
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class BadgeChip extends StatelessWidget {
  const BadgeChip(this.badge, {super.key, this.dense = false});
  final String badge;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final s = badgeStyle(badge);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 5),
      decoration: BoxDecoration(color: s.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.icon, size: dense ? 11 : 14, color: s.color),
        const SizedBox(width: 4),
        Text(badge, style: TextStyle(color: s.color, fontWeight: FontWeight.w600, fontSize: dense ? 10 : 12)),
      ]),
    );
  }
}

class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 14, this.count});
  final double value;
  final double size;
  final int? count;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(
          value >= i ? Icons.star_rounded : (value >= i - .5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size,
          color: const Color(0xFFFFB400),
        ),
      const SizedBox(width: 4),
      Text(value.toStringAsFixed(1), style: TextStyle(fontSize: size - 1, fontWeight: FontWeight.w600)),
      if (count != null) Text(' ($count)', style: TextStyle(fontSize: size - 2, color: Colors.grey)),
    ]);
  }
}

class ScorePill extends StatelessWidget {
  const ScorePill(this.score, {super.key, this.label = 'En İyi Seçim'});
  final double score;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = score >= 70 ? AppColors.buy : (score >= 50 ? AppColors.wait : AppColors.dontBuy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
      child: Text('$label ${score.toStringAsFixed(0)}',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile(this.p, {super.key, this.width = 170, this.trailing});
  final ProductCard p;
  final double width;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/product/${p.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                NetImage(p.image),
                Positioned(left: 6, top: 6, child: ScorePill(p.bestChoice)),
                if (p.badges.contains('Yüksek Riskli'))
                  const Positioned(right: 6, top: 6, child: BadgeChip('Yüksek Riskli', dense: true)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Stars(p.aiRating > 0 ? p.aiRating : p.rating, size: 12, count: p.ratingCount),
                const SizedBox(height: 4),
                Text(tl(p.price), style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                if (p.badges.where((b) => b != 'Yüksek Riskli').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  BadgeChip(p.badges.firstWhere((b) => b != 'Yüksek Riskli'), dense: true),
                ],
                if (trailing != null) trailing!,
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class ProductRow extends StatelessWidget {
  const ProductRow(this.p, {super.key, this.subtitle, this.trailing, this.onTap});
  final ProductCard p;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap ?? () => context.push('/product/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 84, height: 84, child: NetImage(p.image, radius: 12)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  Stars(p.aiRating > 0 ? p.aiRating : p.rating, size: 12, count: p.ratingCount),
                  const Spacer(),
                  ScorePill(p.bestChoice),
                ]),
                const SizedBox(height: 4),
                Text(tl(p.price), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Theme.of(context).colorScheme.primary)),
                if (p.badges.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, children: p.badges.map((b) => BadgeChip(b, dense: true)).toList()),
                ],
                if (subtitle != null) ...[const SizedBox(height: 6), subtitle!],
              ]),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.icon});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6)],
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

/// FutureBuilder + yükleniyor/hata/yeniden dene kalıbı
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.future, required this.builder, this.onRetry});
  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (snap.hasError) return ErrorView(snap.error.toString(), onRetry: onRetry);
        return builder(snap.data as T);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
        ]),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          ]),
        ),
      );
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
