import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';

/// Yönetici Paneli: hak ihlali/itiraz bildirimleri ve kullanıcı şikayetleri.
/// Yalnızca yönetici hesaplarda Profil ekranında görünür.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  static const kindLabels = {
    'marka_itirazi': 'Marka / bilgi itirazı',
    'icerik_kaldirma': 'İçerik kaldırma / hak ihlali',
    'kvkk_basvurusu': 'KVKK başvurusu',
    'diger': 'Diğer',
  };
  late Future<List<dynamic>> future = load();

  Future<List<dynamic>> load() {
    final api = ref.read(apiProvider);
    return Future.wait([api.get('/admin/notices'), api.get('/admin/reports')]);
  }

  void reload() => setState(() => future = load());

  Future<void> resolveNotice(Map n, bool accept) async {
    final note = TextEditingController();
    var hide = accept && n['target_type'] != null && n['target_type'] != 'product';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(accept ? 'Bildirimi kabul et' : 'Bildirimi reddet'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Karar notu (kendi kaydınız için)')),
            if (accept && n['target_type'] != null && n['target_type'] != 'product')
              CheckboxListTile(value: hide, onChanged: (v) => set(() => hide = v ?? false), title: const Text('İlgili içeriği gizle')),
            const SizedBox(height: 8),
            Text('Bildirim sahibine ${n['email']} adresinden e-postayla kararınızı bildirmeyi unutmayın.',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(apiProvider).post('/admin/notices/${n['id']}', {'accept': accept, 'hide_target': hide, 'resolution': note.text});
    reload();
  }

  Future<void> resolveReport(Map r, bool hide) async {
    await ref.read(apiProvider).post('/admin/reports/resolve', {'target_type': r['target_type'], 'target_id': r['target_id'], 'hide': hide});
    if (mounted) toast(context, hide ? 'İçerik gizlendi' : 'Şikayet reddedildi, içerik yayında');
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yönetici Paneli'),
          actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh))],
          bottom: const TabBar(tabs: [Tab(text: 'Hak ihlali / itirazlar'), Tab(text: 'Kullanıcı şikayetleri')]),
        ),
        body: AsyncView<List<dynamic>>(
          future: future,
          onRetry: reload,
          builder: (d) {
            final notices = List<Map>.from(d[0]);
            final reports = List<Map>.from(d[1]);
            return TabBarView(children: [
              notices.isEmpty
                  ? const EmptyView('Bekleyen bildirim yok.', icon: Icons.check_circle_outline)
                  : ListView(padding: const EdgeInsets.all(8), children: [
                      for (final n in notices)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(kindLabels[n['kind']] ?? n['kind'], style: const TextStyle(fontWeight: FontWeight.w700))),
                                _DaysChip((n['days_open'] as num).toDouble()),
                              ]),
                              Text('${n['name']} · ${n['email']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              if (n['target_type'] != null) Text('Hedef: ${n['target_type']} #${n['target_id']}', style: const TextStyle(fontSize: 12)),
                              if ((n['target'] as Map?)?['text'] != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.all(8),
                                  color: Colors.black12,
                                  child: Text('İçerik: ${n['target']['text']}'),
                                ),
                              const SizedBox(height: 6),
                              Text(n['description']),
                              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                TextButton(onPressed: () => resolveNotice(n, false), child: const Text('Reddet')),
                                FilledButton(onPressed: () => resolveNotice(n, true), child: const Text('Kabul et')),
                              ]),
                            ]),
                          ),
                        ),
                    ]),
              reports.isEmpty
                  ? const EmptyView('Bekleyen şikayet yok.', icon: Icons.check_circle_outline)
                  : ListView(padding: const EdgeInsets.all(8), children: [
                      for (final r in reports)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${r['target_type']} #${r['target_id']} · ${r['count']} şikayet${r['is_hidden'] == true ? ' · şu an gizli' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('Nedenler: ${List.from(r['reasons']).toSet().join(', ')}', style: const TextStyle(fontSize: 12)),
                              if (r['text'] != null)
                                Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(8), color: Colors.black12, child: Text(r['text'])),
                              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                TextButton(onPressed: () => resolveReport(r, false), child: const Text('Yayında tut')),
                                FilledButton(onPressed: () => resolveReport(r, true), child: const Text('Gizle')),
                              ]),
                            ]),
                          ),
                        ),
                    ]),
            ]);
          },
        ),
      ),
    );
  }
}

/// 7 günlük süreye ne kadar kaldığını renkle gösterir.
class _DaysChip extends StatelessWidget {
  const _DaysChip(this.days);
  final double days;
  @override
  Widget build(BuildContext context) {
    final left = 7 - days;
    final c = left <= 1 ? Colors.red : (left <= 3 ? Colors.orange : Colors.green);
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: c.withValues(alpha: .15),
      label: Text(left <= 0 ? 'SÜRE DOLDU' : '${left.ceil()} gün kaldı', style: TextStyle(color: c, fontSize: 11)),
    );
  }
}
