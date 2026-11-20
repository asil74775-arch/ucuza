import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';

/// Google Play kullanıcı içeriği (UGC) politikası: şikayet ve engelleme.
Future<void> reportContent(BuildContext context, WidgetRef ref, String type, int id) async {
  final reasons = ['Spam veya reklam', 'Sahte/yanıltıcı', 'Hakaret veya taciz', 'Uygunsuz içerik', 'Diğer'];
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(8), child: Text('Şikayet nedeni', style: TextStyle(fontWeight: FontWeight.w700))),
        for (final r in reasons) ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
      ]),
    ),
  );
  if (reason == null) return;
  await ref.read(apiProvider).post('/reports', {'target_type': type, 'target_id': id, 'reason': reason});
  if (context.mounted) toast(context, 'Teşekkürler, şikayetin incelenecek.');
}

Future<void> blockUser(BuildContext context, WidgetRef ref, int userId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kullanıcı engellensin mi?'),
      content: const Text('Bu kullanıcının paylaşımlarını görmeyeceksin ve sana mesaj gönderemeyecek.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Engelle')),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(apiProvider).post('/blocks/$userId');
  if (context.mounted) toast(context, 'Kullanıcı engellendi.');
}
