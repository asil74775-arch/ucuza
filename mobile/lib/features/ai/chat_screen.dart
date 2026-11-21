import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import '../legal/legal.dart';

/// Genel yapay zeka sohbeti: katalog + En İyi Seçim sıralaması üzerinden öneri yapar.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  int? sessionId;
  final msgs = <Map<String, dynamic>>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  bool thinking = false;
  static const suggestions = [
    'Oyun için 35.000 TL altı en iyi laptop hangisi?',
    'Pil ömrü uzun telefon istiyorum, ne almalıyım?',
    'Gürültü engellemeli uygun fiyatlı kulaklık öner',
  ];

  Future<void> send(String text) async {
    if (text.trim().isEmpty || thinking) return;
    final api = ref.read(apiProvider);
    setState(() {
      msgs.add({'role': 'user', 'text': text});
      thinking = true;
    });
    input.clear();
    try {
      sessionId ??= (await api.post<Map>('/ai/sessions', {'mode': 'general'}))['id'];
      final r = await api.post<Map<String, dynamic>>('/ai/sessions/$sessionId/chat', {'text': text});
      setState(() => msgs.add(r));
    } catch (e) {
      setState(() => msgs.add({'role': 'model', 'text': 'Üzgünüm, bir hata oluştu: $e'}));
    }
    setState(() => thinking = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yapay Zeka Sohbeti')),
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  const Icon(Icons.auto_awesome, size: 48),
                  const SizedBox(height: 12),
                  const Text('Ne aradığını anlat; En İyi Seçim sıralamasına göre sana en uygun ürünü söyleyeyim.', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(aiDisclaimer, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 16),
                  for (final s in suggestions) Card(child: ListTile(title: Text(s), onTap: () => send(s))),
                ])
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length + (thinking ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == msgs.length) return const _Bubble(text: 'Düşünüyorum…', user: false);
                    final m = msgs[i];
                    final cards = List<Map<String, dynamic>>.from(((m['data']?['cards']) as List? ?? const []).map((e) => Map<String, dynamic>.from(e)));
                    return Column(crossAxisAlignment: m['role'] == 'user' ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                      _Bubble(text: m['text'] ?? '', user: m['role'] == 'user'),
                      if (cards.isNotEmpty)
                        SizedBox(
                          height: 300,
                          child: ListView(scrollDirection: Axis.horizontal, children: cards.map((c) => ProductTile(ProductCard.fromJson(c))).toList()),
                        ),
                    ]);
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
                  textInputAction: TextInputAction.send,
                  onSubmitted: send,
                  decoration: const InputDecoration(hintText: 'Mesajını yaz…'),
                ),
              ),
              IconButton.filled(onPressed: () => send(input.text), icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.user});
  final String text;
  final bool user;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: user ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(text, style: TextStyle(color: user ? cs.onPrimary : cs.onSurface)),
      ),
    );
  }
}
