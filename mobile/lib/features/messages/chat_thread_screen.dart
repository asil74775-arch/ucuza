import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../social/moderation.dart';

/// Kullanıcılar arası anlık mesajlaşma (WebSocket; bağlantı koparsa REST'e düşer).
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversationId, required this.title});
  final int conversationId;
  final String title;
  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final msgs = <Map<String, dynamic>>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  WebSocketChannel? ws;
  StreamSubscription? sub;
  bool otherTyping = false;
  Timer? typingTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _connect();
  }

  Future<void> _load() async {
    final l = await ref.read(apiProvider).get<List>('/conversations/${widget.conversationId}/messages');
    setState(() => msgs
      ..clear()
      ..addAll(l.map((e) => Map<String, dynamic>.from(e))));
    _bottom();
  }

  void _connect() {
    final token = ref.read(apiProvider).token;
    if (token == null || demoMode) return;
    ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws?token=$token'));
    sub = ws!.stream.listen((raw) {
      final ev = jsonDecode(raw as String) as Map<String, dynamic>;
      if (ev['type'] == 'message' && ev['message']['conversation_id'] == widget.conversationId) {
        if (msgs.any((m) => m['id'] == ev['message']['id'])) return;
        setState(() {
          msgs.add(Map<String, dynamic>.from(ev['message']));
          otherTyping = false;
        });
        _bottom();
      } else if (ev['type'] == 'typing' && ev['conversation_id'] == widget.conversationId) {
        setState(() => otherTyping = true);
        typingTimer?.cancel();
        typingTimer = Timer(const Duration(seconds: 3), () => mounted ? setState(() => otherTyping = false) : null);
      } else if (ev['type'] == 'error' && mounted) {
        toast(context, ev['detail'].toString());
      }
    }, onDone: () => Future.delayed(const Duration(seconds: 3), () => mounted ? _connect() : null), onError: (_) {});
  }

  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
      });

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    if (ws != null && ws!.closeCode == null) {
      ws!.sink.add(jsonEncode({'type': 'send', 'conversation_id': widget.conversationId, 'text': t}));
    } else {
      try {
        final m = await ref.read(apiProvider).post<Map<String, dynamic>>('/conversations/${widget.conversationId}/messages', {'text': t});
        setState(() => msgs.add(m));
        _bottom();
      } catch (e) {
        if (mounted) toast(context, e.toString());
      }
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    ws?.sink.close();
    typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user?['id'];
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title),
          if (otherTyping) const Text('yazıyor…', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              final otherId = msgs.firstWhere((m) => m['sender_id'] != me, orElse: () => {})['sender_id'];
              if (v == 'report') reportContent(context, ref, 'message', widget.conversationId);
              if (v == 'block' && otherId != null) blockUser(context, ref, otherId);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Şikayet et')),
              PopupMenuItem(value: 'block', child: Text('Engelle')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[i];
              final mine = m['sender_id'] == me;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .75),
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: mine ? cs.primary : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(m['text'], style: TextStyle(color: mine ? cs.onPrimary : cs.onSurface)),
                    Text(DateFormat('HH:mm').format(DateTime.parse(m['created_at']).toLocal()),
                        style: TextStyle(fontSize: 10, color: (mine ? cs.onPrimary : cs.onSurface).withValues(alpha: .7))),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => ws?.sink.add(jsonEncode({'type': 'typing', 'conversation_id': widget.conversationId})),
                  decoration: const InputDecoration(hintText: 'Mesaj yaz…'),
                ),
              ),
              IconButton.filled(onPressed: send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
