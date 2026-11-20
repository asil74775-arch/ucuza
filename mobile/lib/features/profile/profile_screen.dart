import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(radius: 28, child: Text((user?['display_name'] ?? '?').toString().characters.first)),
          title: Text(user?['display_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(user?['email'] ?? ''),
        ),
        const Divider(),
        ListTile(leading: const Icon(Icons.tune), title: const Text('Kişisel Zevk Profili'), subtitle: const Text('Sonuçların sana göre sıralanması'), onTap: () => context.push('/taste')),
        ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('Mesajlar'), onTap: () => context.push('/messages')),
        ExpansionTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Sahip olduğum ürünler'),
          children: [
            FutureBuilder<List>(
              future: ref.read(apiProvider).get<List>('/ownership'),
              builder: (_, s) => !s.hasData
                  ? const LinearProgressIndicator()
                  : Column(children: [
                      if (s.data!.isEmpty) const ListTile(title: Text('Henüz yok')),
                      for (final p in s.data!) ProductRow(ProductCard.fromJson(Map<String, dynamic>.from(p))),
                    ]),
            ),
          ],
        ),
        ListTile(leading: const Icon(Icons.construction), title: const Text('Projelerim'), onTap: () => context.go('/cart')),
        const Divider(),
        ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Gizlilik Politikası'), onTap: () => launchUrl(Uri.parse('https://kiyaslio.com/gizlilik'))),
        ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Kullanım Koşulları'), onTap: () => launchUrl(Uri.parse('https://kiyaslio.com/kosullar'))),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Affiliate bilgilendirmesi'),
          subtitle: Text('Kıyaslio, satıcı bağlantıları üzerinden yapılan alışverişlerden komisyon alabilir. Bu, sıralamaları etkilemez.'),
        ),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Çıkış yap'), onTap: () => ref.read(authProvider.notifier).logout()),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('Hesabımı ve verilerimi sil', style: TextStyle(color: Colors.red)),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Hesap silinsin mi?'),
                content: const Text('Hesabın, paylaşımların, mesajların ve tüm kişisel verilerin kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Kalıcı olarak sil')),
                ],
              ),
            );
            if (ok == true) {
              try {
                await ref.read(authProvider.notifier).deleteAccount();
              } catch (e) {
                if (context.mounted) toast(context, e.toString());
              }
            }
          },
        ),
        const SizedBox(height: 24),
        const Center(child: Text('Kıyaslio v1.0.0', style: TextStyle(color: Colors.grey))),
        const SizedBox(height: 24),
      ]),
    );
  }
}
