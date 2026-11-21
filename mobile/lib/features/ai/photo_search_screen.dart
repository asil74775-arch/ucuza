import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import 'verdict_card.dart';

/// Fotoğraf çek veya galeriden seç → ürün tanı → "almaya değer mi?" analizi.
class PhotoSearchScreen extends ConsumerStatefulWidget {
  const PhotoSearchScreen({super.key});
  @override
  ConsumerState<PhotoSearchScreen> createState() => _PhotoSearchScreenState();
}

class _PhotoSearchScreenState extends ConsumerState<PhotoSearchScreen> {
  Uint8List? imageBytes;
  bool loading = false;
  double upload = 0;
  Map<String, dynamic>? result;
  String? error;

  Future<void> pick(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, imageQuality: 85, maxWidth: 1920);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      imageBytes = bytes;
      result = null;
      error = null;
      loading = true;
      upload = 0;
    });
    try {
      final r = await ref.read(apiProvider).upload<Map<String, dynamic>>(
            '/ai/photo-search',
            FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: f.name)}),
            onProgress: (p) => setState(() => upload = p),
          );
      if (mounted) setState(() { result = r; loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { loading = false; error = e.toString(); });
        toast(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final res = result;
    return Scaffold(
      appBar: AppBar(title: const Text('Fotoğrafla Ürün Ara')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'Ürünün fotoğrafını çek veya galeriden seç. Yapay zeka markayı ve modeli tanır, '
          'fiyat geçmişini ve kullanıcı yorumlarını analiz ederek almaya değip değmeyeceğini söyler.',
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: loading ? null : () => pick(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Fotoğraf Çek'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loading ? null : () => pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Galeriden'),
            ),
          ),
        ]),

        if (imageBytes != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              imageBytes!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],

        if (loading) ...[
          const SizedBox(height: 16),
          if (upload < 1)
            LinearProgressIndicator(value: upload)
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(
            upload < 1
                ? 'Yükleniyor %${(upload * 100).toStringAsFixed(0)}'
                : 'Ürün tanınıyor…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],

        if (error != null) ErrorView(error!),

        if (res != null) ...[
          const SizedBox(height: 16),
          if (res['product'] == null)
            EmptyView(res['message'] ?? 'Ürün bulunamadı', icon: Icons.search_off)
          else ...[
            _DetectionChip(res['detected'] as Map?),
            const SizedBox(height: 8),
            if (res['added_to_catalog'] == true)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.add_circle, color: Colors.green),
                  title: const Text('Yeni ürün! Sistemde yoktu, internetten bulunup kataloğa eklendi.'),
                ),
              ),
            ProductRow(ProductCard.fromJson(Map<String, dynamic>.from(res['product']))),
            if ((res['fake_reviews_removed'] as int? ?? 0) > 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gpp_maybe),
                  title: Text('${res['fake_reviews_removed']} sahte/şüpheli yorum ayıklandı'),
                  subtitle: Text(
                    '90 günlük fiyat: en düşük ${tl(res['price_stats']?['min'])}, '
                    'ortalama ${tl(res['price_stats']?['avg'])}',
                  ),
                ),
              ),
            VerdictCard(Map<String, dynamic>.from(res['verdict'])),
            for (final a in List.from(res['alternatives'] ?? const []))
              ProductRow(
                ProductCard.fromJson(Map<String, dynamic>.from(a)),
                subtitle: Text('Alternatif · %${a['saving_pct']} daha ucuz'),
              ),
          ],
        ],
      ]),
    );
  }
}

class _DetectionChip extends StatelessWidget {
  final Map? det;
  const _DetectionChip(this.det);
  @override
  Widget build(BuildContext context) {
    if (det == null) return const SizedBox.shrink();
    final pct = ((det!['confidence'] as num? ?? 0) * 100).toStringAsFixed(0);
    final name = det!['full_name'] ?? det!['brand'] ?? '';
    return Chip(
      avatar: const Icon(Icons.verified, size: 18),
      label: Text('$name — %$pct güven'),
    );
  }
}
