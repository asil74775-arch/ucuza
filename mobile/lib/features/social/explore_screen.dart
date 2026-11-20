import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import 'moderation.dart';

/// "Keşfet": Gerçek Kullanıcı Deneyimi akışı (kısa yorum + foto + video).
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final items = <Map<String, dynamic>>[];
  bool loading = false, done = false;
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    more();
    scroll.addListener(() {
      if (scroll.position.pixels > scroll.position.maxScrollExtent - 600) more();
    });
  }

  Future<void> more({bool reset = false}) async {
    if (loading || (done && !reset)) return;
    loading = true;
    if (reset) {
      items.clear();
      done = false;
    }
    try {
      final l = await ref.read(apiProvider).get<List>('/explore', {'limit': 20, 'offset': items.length});
      items.addAll(l.map((e) => Map<String, dynamic>.from(e)));
      done = l.length < 20;
    } catch (_) {}
    loading = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keşfet')),
      body: RefreshIndicator(
        onRefresh: () => more(reset: true),
        child: items.isEmpty && !loading
            ? ListView(children: const [EmptyView('Henüz paylaşım yok. Bir ürün sayfasından deneyimini paylaş!')])
            : ListView.builder(
                controller: scroll,
                itemCount: items.length + (done ? 0 : 1),
                itemBuilder: (_, i) => i == items.length
                    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                    : ExperienceCard(items[i]),
              ),
      ),
    );
  }
}

class ExperienceCard extends ConsumerStatefulWidget {
  const ExperienceCard(this.e, {super.key, this.compact = false});
  final Map<String, dynamic> e;
  final bool compact;
  @override
  ConsumerState<ExperienceCard> createState() => _ExperienceCardState();
}

class _ExperienceCardState extends ConsumerState<ExperienceCard> {
  late bool liked = widget.e['liked'] ?? false;
  late int likes = widget.e['like_count'] ?? 0;

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    final media = List<Map>.from(e['media'] ?? const []);
    final me = ref.watch(authProvider).user?['id'];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          leading: CircleAvatar(child: Text((e['user']['name'] as String).characters.first)),
          title: Row(children: [
            Flexible(child: Text(e['user']['name'], overflow: TextOverflow.ellipsis)),
            if (e['verified_purchase'] == true) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 16, color: Colors.blue),
            ],
          ]),
          subtitle: Text(DateFormat('d MMM y', 'tr_TR').format(DateTime.parse(e['created_at']))),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'msg') {
                final c = await ref.read(apiProvider).post<Map>('/conversations', {'user_id': e['user']['id'], 'product_id': e['product']['id']});
                if (context.mounted) context.push('/messages/${c['id']}', extra: e['user']['name']);
              } else if (v == 'report') {
                await reportContent(context, ref, 'experience', e['id']);
              } else if (v == 'block') {
                await blockUser(context, ref, e['user']['id']);
              }
            },
            itemBuilder: (_) => [
              if (me != e['user']['id']) const PopupMenuItem(value: 'msg', child: Text('Mesaj gönder')),
              const PopupMenuItem(value: 'report', child: Text('Şikayet et')),
              if (me != e['user']['id']) const PopupMenuItem(value: 'block', child: Text('Kullanıcıyı engelle')),
            ],
          ),
        ),
        if (!widget.compact)
          InkWell(
            onTap: () => context.push('/product/${e['product']['id']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                SizedBox(width: 32, height: 32, child: NetImage(e['product']['image'], radius: 6)),
                const SizedBox(width: 8),
                Expanded(child: Text(e['product']['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stars((e['rating'] as num).toDouble()),
            const SizedBox(height: 4),
            Text(e['text']),
          ]),
        ),
        if (media.isNotEmpty)
          SizedBox(
            height: widget.compact ? 120 : 240,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              children: media
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AspectRatio(
                          aspectRatio: widget.compact ? 1 : 3 / 4,
                          child: m['type'] == 'video' ? _VideoThumb(m['url']) : NetImage(m['url'], radius: 12),
                        ),
                      ))
                  .toList(),
            ),
          ),
        Row(children: [
          IconButton(
            icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null),
            onPressed: () async {
              final r = await ref.read(apiProvider).post<Map>('/experiences/${e['id']}/like');
              setState(() {
                liked = r['liked'];
                likes = r['like_count'];
              });
            },
          ),
          Text('$likes'),
        ]),
      ]),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb(this.url);
  final String url;
  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  late final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  @override
  void initState() {
    super.initState();
    c.initialize().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Colors.black),
            if (c.value.isInitialized) FittedBox(fit: BoxFit.cover, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
            if (!c.value.isPlaying) const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 48)),
          ]),
        ),
      );
}
