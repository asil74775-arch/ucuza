import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';
import '../ai/verdict_card.dart';

/// Video ile ürün keşfi + "almaya değer mi?" analizi.
class VideoScreen extends ConsumerStatefulWidget {
  const VideoScreen({super.key});
  @override
  ConsumerState<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends ConsumerState<VideoScreen> {
  VideoPlayerController? player;
  double upload = 0;
  String? stage;
  Map<String, dynamic>? job;
  Timer? poll;

  Future<void> pick(ImageSource src) async {
    final f = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(minutes: 3));
    if (f == null) return;
    player?.dispose();
    player = VideoPlayerController.networkUrl(Uri.file(f.path));
    await player!.initialize();
    player!.setLooping(true);
    player!.play();
    setState(() {
      job = null;
      stage = 'Yükleniyor';
    });
    try {
      final r = await ref.read(apiProvider).upload<Map<String, dynamic>>(
            '/ai/video',
            FormData.fromMap({'file': await MultipartFile.fromFile(f.path, filename: f.name)}),
            onProgress: (p) => setState(() => upload = p),
          );
      _poll(r['job_id']);
    } catch (e) {
      if (mounted) toast(context, e.toString());
      setState(() => stage = null);
    }
  }

  void _poll(int id) {
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      final j = await ref.read(apiProvider).get<Map<String, dynamic>>('/ai/video/$id');
      if (!mounted) return t.cancel();
      setState(() {
        stage = j['stage'];
        if (j['status'] == 'done' || j['status'] == 'failed') {
          job = j;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    poll?.cancel();
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final res = job?['result'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('Video ile Ürün Analizi')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Bir ürün videosu yükle (inceleme, reklam, sosyal medya videosu). Yapay zeka ürünü tespit eder, '
            'sistemde yoksa internetten bulup ekler; yorumları, sahte yorumları, fiyat geçmişini ve alternatifleri '
            'kontrol ederek almaya değip değmeyeceğini söyler.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () => pick(ImageSource.gallery), icon: const Icon(Icons.video_library), label: const Text('Galeriden'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () => pick(ImageSource.camera), icon: const Icon(Icons.videocam), label: const Text('Kaydet'))),
        ]),
        if (player != null && player!.value.isInitialized) ...[
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(16), child: AspectRatio(aspectRatio: player!.value.aspectRatio, child: VideoPlayer(player!))),
        ],
        if (stage != null && job == null) ...[
          const SizedBox(height: 16),
          if (upload < 1) LinearProgressIndicator(value: upload) else const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(upload < 1 ? 'Yükleniyor %${(upload * 100).toStringAsFixed(0)}' : stage ?? ''),
        ],
        if (job?['status'] == 'failed') ErrorView('Analiz başarısız: ${job!['error']}'),
        if (res != null) ...[
          const SizedBox(height: 16),
          if (res['product'] == null)
            EmptyView(res['message'] ?? 'Ürün bulunamadı', icon: Icons.search_off)
          else ...[
            if (res['added_to_catalog'] == true)
              const Card(child: ListTile(leading: Icon(Icons.add_circle, color: Colors.green), title: Text('Bu ürün sistemde yoktu; internetten bulunup kataloğa eklendi.'))),
            Text('Tespit edilen ürün (güven %${(((res['detected']?['confidence'] ?? 0) as num) * 100).toStringAsFixed(0)})',
                style: const TextStyle(color: Colors.grey)),
            ProductRow(ProductCard.fromJson(Map<String, dynamic>.from(res['product']))),
            if (res['warning'] != null)
              Card(color: Colors.orange.withValues(alpha: .1), child: ListTile(leading: const Icon(Icons.campaign), title: Text(res['warning']))),
            Card(
              child: ListTile(
                leading: const Icon(Icons.gpp_maybe),
                title: Text('${res['fake_reviews_removed']} sahte/şüpheli yorum ayıklandı'),
                subtitle: Text('90 günlük fiyat: en düşük ${tl(res['price_stats']?['min'])}, ortalama ${tl(res['price_stats']?['avg'])}'),
              ),
            ),
            VerdictCard(Map<String, dynamic>.from(res['verdict'])),
            for (final a in List.from(res['alternatives'] ?? const []))
              ProductRow(ProductCard.fromJson(Map<String, dynamic>.from(a)), subtitle: Text('Alternatif · %${a['saving_pct']} daha ucuz')),
          ],
        ],
      ]),
    );
  }
}
