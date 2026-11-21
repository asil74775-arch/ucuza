import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/widgets.dart';

/// Satın aldıktan sonra kısa yorum + fotoğraf + video paylaşımı (Keşfet & Bizden Alanlar)
class CreateExperienceScreen extends ConsumerStatefulWidget {
  const CreateExperienceScreen({super.key, required this.productId});
  final int productId;
  @override
  ConsumerState<CreateExperienceScreen> createState() => _CreateExperienceScreenState();
}

class _CreateExperienceScreenState extends ConsumerState<CreateExperienceScreen> {
  final text = TextEditingController();
  int rating = 5;
  final files = <XFile>[];
  double progress = 0;
  bool busy = false;

  Future<void> addMedia(bool video) async {
    final picker = ImagePicker();
    if (video) {
      final v = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
      if (v != null) setState(() => files.add(v));
    } else {
      final imgs = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
      setState(() => files.addAll(imgs.take(6 - files.length)));
    }
  }

  Future<void> submit() async {
    if (text.text.trim().length < 5) return toast(context, 'Biraz daha yaz (en az 5 karakter)');
    setState(() => busy = true);
    try {
      final form = FormData.fromMap({
        'product_id': widget.productId,
        'text': text.text.trim(),
        'rating': rating,
        'files': [for (final f in files) MultipartFile.fromBytes(await f.readAsBytes(), filename: f.name)],
      });
      await ref.read(apiProvider).upload('/experiences', form, onProgress: (p) => setState(() => progress = p));
      if (mounted) {
        toast(context, 'Deneyimin paylaşıldı!');
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
      appBar: AppBar(title: const Text('Yorum Yaz')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 36,
              onPressed: () => setState(() => rating = i),
              icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFFB400)),
            ),
        ]),
        TextField(
          controller: text,
          maxLines: 5,
          maxLength: 1000,
          decoration: const InputDecoration(hintText: 'Ürünü ne kadar süredir kullanıyorsun? Neyi sevdin, neyi sevmedin?'),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in files)
            Chip(label: Text(f.name, overflow: TextOverflow.ellipsis), onDeleted: () => setState(() => files.remove(f))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: files.length >= 6 ? null : () => addMedia(false), icon: const Icon(Icons.photo), label: const Text('Fotoğraf'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: files.length >= 6 ? null : () => addMedia(true), icon: const Icon(Icons.videocam), label: const Text('Video'))),
        ]),
        const SizedBox(height: 16),
        if (busy) LinearProgressIndicator(value: progress > 0 && progress < 1 ? progress : null),
        const SizedBox(height: 8),
        FilledButton(onPressed: busy ? null : submit, child: const Text('Paylaş')),
        const SizedBox(height: 8),
        const Text('Yorumun Keşfet akışında ve ürün sayfasındaki "Bizden Alanlar" bölümünde görünür ve ürün puanına katılır. '
            'Her ürüne bir yorum yazabilirsin. Sahte, kopyalanmış veya sponsorlu olduğu tespit edilen yorumlar ile '
            'bağlantı, iletişim bilgisi ve hakaret içerenler kaldırılır.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}
