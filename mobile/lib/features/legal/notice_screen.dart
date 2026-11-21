import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import 'legal.dart';

/// Hak ihlali bildirimi, içerik kaldırma, marka itirazı ve KVKK başvurusu formu.
class NoticeScreen extends ConsumerStatefulWidget {
  const NoticeScreen({super.key, this.target});
  /// {'type': 'product'|'experience'|..., 'id': 1, 'label': 'Ürün adı'}
  final Map<String, dynamic>? target;
  @override
  ConsumerState<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends ConsumerState<NoticeScreen> {
  static const kinds = {
    'marka_itirazi': 'Ürün/marka bilgisi hatalı (itiraz)',
    'icerik_kaldirma': 'Hukuka aykırı içerik / hak ihlali',
    'kvkk_basvurusu': 'Kişisel verilerimle ilgili başvuru (KVKK)',
    'diger': 'Diğer',
  };
  late String kind = widget.target?['type'] == 'product' ? 'marka_itirazi' : 'icerik_kaldirma';
  late final name = TextEditingController(text: ref.read(authProvider).user?['display_name']);
  late final email = TextEditingController(text: ref.read(authProvider).user?['email']);
  final desc = TextEditingController();
  bool busy = false;

  Future<void> send() async {
    if (desc.text.trim().length < 10) return toast(context, 'Lütfen ayrıntı yazın (en az 10 karakter)');
    setState(() => busy = true);
    try {
      final r = await ref.read(apiProvider).post<Map>('/legal/notices', {
        'kind': kind,
        'name': name.text.trim(),
        'email': email.text.trim(),
        'target_type': widget.target?['type'],
        'target_id': widget.target?['id'],
        'description': desc.text.trim(),
      });
      if (mounted) {
        toast(context, r['message']);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hak ihlali / itiraz bildir')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.target != null)
          Card(child: ListTile(leading: const Icon(Icons.link), title: Text(widget.target!['label'] ?? 'Seçili içerik'))),
        for (final e in kinds.entries)
          RadioListTile<String>(value: e.key, groupValue: kind, title: Text(e.value), onChanged: (v) => setState(() => kind = v!)),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad Soyad / Şirket unvanı')),
        const SizedBox(height: 10),
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta (yanıt için)')),
        const SizedBox(height: 10),
        TextField(
          controller: desc,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Açıklama', hintText: 'Hangi bilgi/içerik, neden hatalı veya hukuka aykırı?'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy ? null : send, child: const Text('Gönder')),
        const SizedBox(height: 8),
        const Text('Bildirimler en geç 7 gün içinde incelenir. Haklı bulunan içerik kaldırılır veya düzeltilir.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        const LegalLink('yontem', label: 'Puan ve etiketler nasıl hesaplanıyor?'),
      ]),
    );
  }
}
