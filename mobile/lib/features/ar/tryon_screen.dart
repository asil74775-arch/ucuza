import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Üzerinde deneme (gözlük, kulaklık, şapka, tişört…): ön kamera + yüz tespiti ile
/// şeffaf ürün görselini kullanıcının yüzüne/gövdesine hizalar.
class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key, required this.product});
  final Map<String, dynamic> product;
  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  CameraController? cam;
  final detector = FaceDetector(options: FaceDetectorOptions(enableLandmarks: true, performanceMode: FaceDetectorMode.fast));
  Rect? face;
  Size? imageSize;
  bool busy = false;
  double scale = 1, offsetY = 0;

  bool get isFace => widget.product['ar_type'] == 'wearable_face';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cams = await availableCameras();
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    cam = CameraController(front, ResolutionPreset.medium, enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888);
    await cam!.initialize();
    if (!mounted) return;
    setState(() {});
    cam!.startImageStream((img) async {
      if (busy) return;
      busy = true;
      try {
        final input = _toInput(img, front);
        if (input != null) {
          final faces = await detector.processImage(input);
          if (mounted) {
            setState(() {
              face = faces.isEmpty ? null : faces.first.boundingBox;
              imageSize = Size(img.height.toDouble(), img.width.toDouble()); // portre: döndürülmüş
            });
          }
        }
      } catch (e) {
        debugPrint('tryon: $e');
      }
      busy = false;
    });
  }

  InputImage? _toInput(CameraImage img, CameraDescription d) {
    final rotation = InputImageRotationValue.fromRawValue(d.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(img.format.raw);
    if (rotation == null || format == null || img.planes.length != 1) return null;
    return InputImage.fromBytes(
      bytes: img.planes.first.bytes,
      metadata: InputImageMetadata(size: Size(img.width.toDouble(), img.height.toDouble()), rotation: rotation, format: format,
          bytesPerRow: img.planes.first.bytesPerRow),
    );
  }

  @override
  void dispose() {
    cam?.dispose();
    detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.product['tryon_asset_url'] as String;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Üzerinde Dene'), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: cam == null || !cam!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, box) {
              Widget? overlay;
              if (face != null && imageSize != null) {
                final sx = box.maxWidth / imageSize!.width, sy = box.maxHeight / imageSize!.height;
                // Ön kamera aynalı: x ekseni ters
                final left = box.maxWidth - face!.right * sx;
                final w = face!.width * sx * scale;
                final top = isFace
                    ? face!.top * sy + face!.height * sy * .28 + offsetY // göz hizası
                    : face!.bottom * sy + face!.height * sy * .2 + offsetY; // gövde
                overlay = Positioned(
                  left: left - (w - face!.width * sx) / 2 - (isFace ? 0 : w * .5),
                  top: top,
                  width: isFace ? w : w * 2,
                  child: Image.network(asset, fit: BoxFit.contain),
                );
              }
              return Stack(fit: StackFit.expand, children: [
                CameraPreview(cam!),
                if (overlay != null) overlay,
                if (face == null)
                  const Align(
                    alignment: Alignment(0, -.8),
                    child: Chip(label: Text('Yüzünü kameraya göster')),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.product['name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                        Row(children: [
                          const Icon(Icons.zoom_out_map, size: 18),
                          Expanded(child: Slider(min: .6, max: 1.6, value: scale, onChanged: (v) => setState(() => scale = v))),
                          const Icon(Icons.height, size: 18),
                          Expanded(child: Slider(min: -60, max: 60, value: offsetY, onChanged: (v) => setState(() => offsetY = v))),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ]);
            }),
    );
  }
}
