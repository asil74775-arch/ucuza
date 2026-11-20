import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});
  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  late Future<List> future = ref.read(apiProvider).get<List>('/conversations');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mesajlar')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => future = ref.read(apiProvider).get<List>('/conversations')),
        child: AsyncView<List>(
          future: future,
          builder: (list) => list.isEmpty
              ? ListView(children: const [
                  EmptyView('Henüz mesajın yok.\nSoru-Cevap veya Keşfet üzerinden diğer kullanıcılarla yazışabilirsin.', icon: Icons.forum_outlined),
                ])
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final last = c['last_message'];
                    return ListTile(
                      leading: Badge(
                        isLabelVisible: c['other']?['online'] == true,
                        backgroundColor: Colors.green,
                        smallSize: 10,
                        child: CircleAvatar(child: Text((c['other']?['name'] ?? '?').toString().characters.first)),
                      ),
                      title: Text(c['other']?['name'] ?? 'Kullanıcı'),
                      subtitle: Text(last?['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (last != null) Text(DateFormat('HH:mm').format(DateTime.parse(last['created_at']).toLocal()), style: const TextStyle(fontSize: 11)),
                        if ((c['unread'] ?? 0) > 0) Badge(label: Text('${c['unread']}')),
                      ]),
                      onTap: () async {
                        await context.push('/messages/${c['id']}', extra: c['other']?['name']);
                        setState(() => future = ref.read(apiProvider).get<List>('/conversations'));
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
