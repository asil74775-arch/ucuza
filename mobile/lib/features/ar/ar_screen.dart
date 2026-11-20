import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'tryon_screen.dart';

/// Artırılmış Gerçeklik ile Ürün Önizleme.
///  - furniture / tabletop: 3B model (.glb) Google Scene Viewer (ARCore) ile odaya yerleştirilir.
///  - wearable_face / wearable_body: ön kamera + ML Kit ile kullanıcının üzerinde denenir.
class ArScreen extends StatelessWidget {
  const ArScreen({super.key, required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final type = product['ar_type'] as String?;
    if ((type == 'wearable_face' || type == 'wearable_body') && product['tryon_asset_url'] != null) {
      return TryOnScreen(product: product);
    }
    final model = product['ar_model_url'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text(type == 'furniture' ? 'Odanda Gör' : 'AR Önizleme')),
      body: model == null
          ? const Center(child: Text('Bu ürün için 3B model henüz yok.'))
          : Column(children: [
              Expanded(
                child: ModelViewer(
                  src: model,
                  alt: product['name'],
                  ar: true,
                  arModes: const ['scene-viewer', 'webxr', 'quick-look'],
                  arScale: ArScale.fixed, // gerçek ölçüde yerleştir
                  arPlacement: ArPlacement.floor,
                  autoRotate: true,
                  cameraControls: true,
                  shadowIntensity: 1,
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sağ alttaki AR simgesine dokun, telefonu zemine doğrult ve ürünü gerçek boyutunda odana yerleştir. '
                    'Parmağınla döndürüp taşıyabilirsin.', textAlign: TextAlign.center),
              ),
            ]),
    );
  }
}
