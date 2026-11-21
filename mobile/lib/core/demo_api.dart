import 'dart:convert';

import 'package:dio/dio.dart';

/// Sunucu olmadan uygulamayı denemek için (--dart-define=DEMO=true) tüm API
/// isteklerini örnek verilerle yanıtlar.
class DemoInterceptor extends Interceptor {
  final _db = _DemoDb();

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final o = options;
    final path = Uri.parse(o.path).path;
    final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    Object? data;
    try {
      data = _db.handle(o.method.toUpperCase(), path, o.queryParameters, body);
    } catch (_) {
      data = null;
    }
    data ??= o.method.toUpperCase() == 'GET' ? <Object>[] : <String, Object>{};
    // Gerçek ağ yanıtı gibi Map<String, dynamic> / List<dynamic> tiplerine çevir.
    handler.resolve(Response(requestOptions: o, statusCode: 200, data: jsonDecode(jsonEncode(data))));
  }
}

const _disclaimer = 'Bu analiz otomatik üretilmiştir ve örnek (demo) veriler içerir; kesin bir tavsiye değildir.';

const _user = {
  'id': 1,
  'email': 'demo@fiyatradar.app',
  'display_name': 'Demo Kullanıcı',
  'ai_consent': true,
  'is_admin': false,
};

const _phoneSchema = [
  {'key': 'battery', 'label': 'Batarya', 'unit': ' mAh', 'type': 'number'},
  {'key': 'camera', 'label': 'Ana kamera', 'unit': ' MP', 'type': 'number'},
  {'key': 'ram', 'label': 'RAM', 'unit': ' GB', 'type': 'number'},
  {'key': 'storage', 'label': 'Depolama', 'unit': ' GB', 'type': 'number'},
  {'key': 'screen', 'label': 'Ekran', 'unit': '"', 'type': 'number'},
  {'key': 'charge', 'label': 'Şarj hızı', 'unit': ' W', 'type': 'number'},
  {'key': 'g5', 'label': '5G', 'unit': '', 'type': 'bool'},
];
const _audioSchema = [
  {'key': 'anc', 'label': 'Aktif gürültü engelleme', 'unit': '', 'type': 'bool'},
  {'key': 'battery_h', 'label': 'Pil ömrü', 'unit': ' saat', 'type': 'number'},
  {'key': 'type', 'label': 'Tip', 'unit': '', 'type': 'enum'},
  {'key': 'bt', 'label': 'Bluetooth', 'unit': '', 'type': 'enum'},
];
const _laptopSchema = [
  {'key': 'cpu', 'label': 'İşlemci', 'unit': '', 'type': 'enum'},
  {'key': 'ram', 'label': 'RAM', 'unit': ' GB', 'type': 'number'},
  {'key': 'storage', 'label': 'SSD', 'unit': ' GB', 'type': 'number'},
  {'key': 'screen', 'label': 'Ekran', 'unit': '"', 'type': 'number'},
  {'key': 'weight', 'label': 'Ağırlık', 'unit': ' kg', 'type': 'number'},
];
const _homeSchema = [
  {'key': 'power', 'label': 'Güç', 'unit': ' W', 'type': 'number'},
  {'key': 'capacity', 'label': 'Kapasite', 'unit': ' L', 'type': 'number'},
  {'key': 'warranty', 'label': 'Garanti', 'unit': ' yıl', 'type': 'number'},
];
const _gameSchema = [
  {'key': 'storage', 'label': 'Depolama', 'unit': ' GB', 'type': 'number'},
  {'key': 'resolution', 'label': 'Çözünürlük', 'unit': '', 'type': 'enum'},
];
const _accSchema = [
  {'key': 'material', 'label': 'Malzeme', 'unit': '', 'type': 'enum'},
];

final _categories = [
  {'id': 1, 'slug': 'telefon', 'name': 'Telefon', 'icon': 'smartphone', 'is_accessory': false, 'spec_schema': _phoneSchema},
  {'id': 2, 'slug': 'kulaklik', 'name': 'Kulaklık', 'icon': 'headphones', 'is_accessory': false, 'spec_schema': _audioSchema},
  {'id': 3, 'slug': 'laptop', 'name': 'Laptop', 'icon': 'laptop', 'is_accessory': false, 'spec_schema': _laptopSchema},
  {'id': 4, 'slug': 'ev-yasam', 'name': 'Ev & Yaşam', 'icon': 'chair', 'is_accessory': false, 'spec_schema': _homeSchema},
  {'id': 5, 'slug': 'oyun', 'name': 'Oyun', 'icon': 'sports_esports', 'is_accessory': false, 'spec_schema': _gameSchema},
  {'id': 10, 'slug': 'kilif', 'name': 'Telefon Kılıfı', 'icon': 'phone_android', 'is_accessory': true, 'spec_schema': _accSchema},
  {'id': 11, 'slug': 'sarj', 'name': 'Şarj Aleti', 'icon': 'memory', 'is_accessory': true, 'spec_schema': _accSchema},
];

// id, kategori, ad, marka, model, fiyat, puan, puan sayısı, en iyi seçim, f/p, rozetler, özellikler, açıklama
final _seed = <Map<String, dynamic>>[
  _p(1, 1, 'Samsung Galaxy S24 128 GB', 'Samsung', 'SM-S921B', 34999, 4.6, 12840, 86, 78, ['En İyi Seçim', 'En Güvenilir'],
      {'battery': 4000, 'camera': 50, 'ram': 8, 'storage': 128, 'screen': 6.2, 'charge': 25, 'g5': true},
      'Kompakt amiral gemisi: Exynos 2400, 120 Hz Dynamic AMOLED 2X ekran ve 7 yıl yazılım güncellemesi.'),
  _p(2, 1, 'Apple iPhone 15 128 GB', 'Apple', 'MTP03TU/A', 41999, 4.7, 18320, 82, 66, ['En Güvenilir', 'Popüler Ama Aşırı Pahalı'],
      {'battery': 3349, 'camera': 48, 'ram': 6, 'storage': 128, 'screen': 6.1, 'charge': 20, 'g5': true},
      'A16 Bionic, Dynamic Island ve USB-C ile gelen iPhone 15; 48 MP ana kamera.'),
  _p(3, 1, 'Xiaomi Redmi Note 13 Pro 256 GB', 'Xiaomi', '2312DRA50G', 13499, 4.4, 9650, 84, 92, ['En İyi Fiyat', 'Öğrenciler İçin İdeal'],
      {'battery': 5000, 'camera': 200, 'ram': 8, 'storage': 256, 'screen': 6.67, 'charge': 67, 'g5': false},
      '200 MP kamera, 67 W hızlı şarj ve 120 Hz AMOLED ekranla fiyat/performans şampiyonu.'),
  _p(4, 1, 'Samsung Galaxy A55 128 GB', 'Samsung', 'SM-A556E', 17999, 4.3, 6420, 74, 80, ['Kroniksiz'],
      {'battery': 5000, 'camera': 50, 'ram': 8, 'storage': 128, 'screen': 6.6, 'charge': 25, 'g5': true},
      'Metal kasa, IP67 dayanıklılık ve 4 yıl Android güncellemesi.'),
  _p(5, 2, 'Apple AirPods Pro 2 (USB-C)', 'Apple', 'MTJV3TU/A', 8999, 4.7, 15400, 83, 70, ['En Güvenilir'],
      {'anc': true, 'battery_h': 6, 'type': 'Kulak içi', 'bt': '5.3'},
      'H2 çip, uyarlanabilir ses ve 2 kata kadar daha güçlü aktif gürültü engelleme.'),
  _p(6, 2, 'Sony WH-1000XM5', 'Sony', 'WH1000XM5B.CE7', 11499, 4.6, 7340, 85, 74, ['En İyi Seçim'],
      {'anc': true, 'battery_h': 30, 'type': 'Kulak üstü', 'bt': '5.2'},
      'Sektör lideri gürültü engelleme, 30 saat pil ve 8 mikrofonla net görüşme.'),
  _p(7, 2, 'JBL Tune 520BT', 'JBL', 'JBLT520BTBLKEU', 1299, 4.4, 21800, 78, 90, ['En İyi Fiyat', 'Öğrenciler İçin İdeal'],
      {'anc': false, 'battery_h': 57, 'type': 'Kulak üstü', 'bt': '5.3'},
      'JBL Pure Bass ses, 57 saate varan pil ömrü ve hafif katlanabilir tasarım.'),
  _p(8, 2, 'Xiaomi Redmi Buds 5', 'Xiaomi', 'M2316E1', 999, 4.2, 8900, 72, 88, ['En İyi Fiyat'],
      {'anc': true, 'battery_h': 10, 'type': 'Kulak içi', 'bt': '5.3'},
      '46 dB aktif gürültü engelleme ve kutuyla 40 saat kullanım.'),
  _p(9, 3, 'Lenovo IdeaPad Slim 5 14" Ryzen 7', 'Lenovo', '83DA0040TX', 24999, 4.5, 2140, 81, 84, ['Öğrenciler İçin İdeal', 'Kroniksiz'],
      {'cpu': 'Ryzen 7 8845HS', 'ram': 16, 'storage': 1024, 'screen': 14, 'weight': 1.46},
      'OLED ekran seçeneği, 16 GB RAM ve 1 TB SSD ile hafif ve güçlü.'),
  _p(10, 4, 'Philips Airfryer XXL HD9650', 'Philips', 'HD9650/90', 7499, 4.6, 5630, 80, 76, ['En Güvenilir'],
      {'power': 2225, 'capacity': 7.3, 'warranty': 2},
      'Yağ ayırma teknolojisi ve 1,4 kg kapasiteyle tüm aile için.'),
  _p(11, 4, 'Dyson V15 Detect Absolute', 'Dyson', '394451-01', 27999, 4.5, 3210, 69, 58, ['Popüler Ama Aşırı Pahalı', 'Yüksek Riskli'],
      {'power': 660, 'capacity': 0.76, 'warranty': 2},
      'Lazerle toz algılama ve partikül sayacı olan kablosuz süpürge.'),
  _p(12, 5, 'Sony PlayStation 5 Slim Digital', 'Sony', 'CFI-2016', 22999, 4.8, 11200, 88, 79, ['En İyi Seçim', 'Kroniksiz'],
      {'storage': 1024, 'resolution': '4K'},
      'Daha ince kasa, 1 TB SSD ve DualSense kablosuz kumanda.'),
  _p(20, 10, 'Spigen Ultra Hybrid Galaxy S24 Kılıf', 'Spigen', 'ACS07345', 499, 4.5, 3100, 79, 85, ['En İyi Fiyat'],
      {'material': 'TPU + PC'}, 'Şeffaf arka, darbe emici köşeler.'),
  _p(21, 11, 'Samsung 25W Süper Hızlı Şarj Adaptörü', 'Samsung', 'EP-TA800', 649, 4.6, 8800, 82, 80, ['En Güvenilir'],
      {'material': 'Plastik'}, 'USB-C PD 3.0 PPS destekli orijinal adaptör.'),
];

Map<String, dynamic> _p(int id, int cat, String name, String brand, String model, int price, double rating, int count,
        int best, int fp, List<String> badges, Map<String, dynamic> specs, String desc) =>
    {
      'id': id,
      'category_id': cat,
      'name': name,
      'brand': brand,
      'model_code': model,
      'image': null,
      'images': <String>[],
      'price': price,
      'rating': rating,
      'ai_rating': double.parse((rating - .1).toStringAsFixed(1)),
      'rating_count': count,
      'best_choice_score': best,
      'fp_score': fp,
      'badges': badges,
      'is_chronic_free': badges.contains('Kroniksiz'),
      'ar_type': null,
      'specs': specs,
      'description': desc,
    };

const _sellers = [
  ('Trendyol', 'https://www.trendyol.com/sr?q='),
  ('Hepsiburada', 'https://www.hepsiburada.com/ara?q='),
  ('Amazon Türkiye', 'https://www.amazon.com.tr/s?k='),
  ('N11', 'https://www.n11.com/arama?q='),
  ('MediaMarkt', 'https://www.mediamarkt.com.tr/tr/search.html?query='),
  ('Teknosa', 'https://www.teknosa.com/arama?s='),
  ('Pazarama Mağazası Elektronik Dünyası', 'https://www.pazarama.com/arama?q='),
];

const _chronic = {
  2: [
    {'title': 'Yoğun kullanımda ısınma', 'severity': 'medium', 'share': .08, 'months_active': 6, 'mention_count': 214},
  ],
  11: [
    {'title': 'Batarya 1 yıl sonra hızlı bitiyor', 'severity': 'high', 'share': .14, 'months_active': 9, 'mention_count': 188},
    {'title': 'Tetik kilidi kırılması', 'severity': 'medium', 'share': .06, 'months_active': 5, 'mention_count': 71},
  ],
  3: [
    {'title': 'Ara sıra kamera uygulaması donması', 'severity': 'low', 'share': .04, 'months_active': 4, 'mention_count': 93},
  ],
};

const _badgeBasis = {
  'En İyi Seçim': 'Kategorisindeki ürünler arasında fiyat, yorum, özellik ve dayanıklılık dengesinde ilk %10\'da.',
  'En Güvenilir': 'Sahte yorumlar ayıklandıktan sonra 12 ay boyunca puanı 4,5 üzerinde kaldı.',
  'En İyi Fiyat': 'Şu anki fiyat, son 90 günün en düşük fiyatına %3 yakınlıkta.',
  'Öğrenciler İçin İdeal': 'Bütçe dostu fiyat ve öğrencilerden gelen olumlu yorum oranı yüksek.',
  'Kroniksiz': 'Zaman içinde tekrarlayan bir sorun tespit edilmedi.',
  'Popüler Ama Aşırı Pahalı': 'Çok satıyor fakat benzer özellikteki ürünlerden %20+ pahalı.',
  'Yüksek Riskli': 'Kronik sorun bildirimi oranı kategori ortalamasının 2 katı.',
};

const _people = [
  {'id': 2, 'name': 'Elif K.'},
  {'id': 3, 'name': 'Mert Y.'},
  {'id': 4, 'name': 'Zeynep A.'},
  {'id': 5, 'name': 'Burak T.'},
  {'id': 6, 'name': 'Ayşe D.'},
];

const _reviewTexts = [
  'Bir aydır kullanıyorum, beklentimin üzerinde çıktı. Pil rahat bir gün gidiyor.',
  'Fiyatına göre çok iyi. Kargo hızlıydı, kutusundan eksiksiz çıktı.',
  'Ekran ve performans harika ama şarj aleti kutudan çıkmıyor, ayrıca almak gerekti.',
  'İndirimde aldım, kesinlikle tavsiye ederim. Ses kalitesi beklediğimden iyi.',
  'İlk hafta küçük bir yazılım sorunu oldu, güncelleme ile düzeldi. Genel olarak memnunum.',
];

class _DemoDb {
  final products = {for (final p in _seed) p['id'] as int: p};
  final cart = <Map<String, dynamic>>[];
  final owned = <int>{1, 7};
  final questions = <int, List<Map<String, dynamic>>>{};
  final messages = <int, List<Map<String, dynamic>>>{};
  final liked = <int>{};
  var _nextId = 1000;
  Map<String, dynamic>? taste;

  int get nextId => _nextId++;

  Object? handle(String m, String path, Map<String, dynamic> q, Map<String, dynamic> b) {
    final s = path.split('/').where((e) => e.isNotEmpty).toList();
    int? n(int i) => s.length > i ? int.tryParse(s[i]) : null;
    final head = s.isEmpty ? '' : s[0];

    switch (head) {
      case 'auth':
        if (s.length > 1 && (s[1] == 'login' || s[1] == 'register')) {
          final name = (b['display_name'] ?? '').toString().trim();
          final email = (b['email'] ?? '').toString().trim();
          return {
            'token': 'demo',
            'user': {..._user, if (name.isNotEmpty) 'display_name': name, if (email.isNotEmpty) 'email': email},
          };
        }
        return m == 'GET' ? _user : {};
      case 'profile':
        if (s.length > 1 && s[1] == 'taste') {
          if (m == 'PUT') {
            taste = {...?taste, ...b};
            return {};
          }
          return {
            'labels': {
              'price': 'Uygun fiyat',
              'quality': 'Kalite & dayanıklılık',
              'brand': 'Bilinen marka',
              'design': 'Tasarım',
              'performance': 'Performans',
            },
            'weights': taste?['weights'] ?? {'price': .7, 'quality': .8, 'brand': .4, 'design': .5, 'performance': .6},
            'price_sensitivity': taste?['price_sensitivity'] ?? .6,
          };
        }
        return {};
      case 'home':
        return _home();
      case 'categories':
        final id = n(1);
        if (id != null && s.length > 2 && s[2] == 'facets') return _facets(id);
        return _categories;
      case 'products':
        final id = n(1);
        if (id == null) return _search(q);
        final sub = s.length > 2 ? s[2] : '';
        switch (sub) {
          case '':
            return _detail(id);
          case 'history':
            return _history(id);
          case 'experiences':
            return _experiences(productId: id);
          case 'alternatives':
            return _alternatives(id);
          case 'questions':
            final list = questions.putIfAbsent(id, () => _seedQuestions(id));
            if (m == 'POST') {
              list.insert(0, {'id': nextId, 'text': b['text'], 'user': {'id': 1, 'name': _user['display_name']}, 'answers': <Map<String, dynamic>>[]});
              return {};
            }
            return {'owner_count': 40 + id * 7, 'questions': list};
        }
        return {};
      case 'questions':
        final qid = n(1);
        for (final list in questions.values) {
          for (final qq in list) {
            if (qq['id'] == qid) {
              (qq['answers'] as List).add({
                'id': nextId,
                'text': b['text'],
                'user': {'id': 1, 'name': _user['display_name']},
                'is_owner': true,
                'helpful_count': 0,
              });
            }
          }
        }
        return {};
      case 'answers':
        final aid = n(1);
        for (final list in questions.values) {
          for (final qq in list) {
            for (final a in qq['answers'] as List) {
              if (a['id'] == aid) a['helpful_count'] = (a['helpful_count'] as int) + 1;
            }
          }
        }
        return {};
      case 'ownership':
        final id = n(1);
        if (id != null) {
          owned.add(id);
          return {};
        }
        return [for (final i in owned) if (products[i] != null) _card(products[i]!)];
      case 'cart':
        return _cart(m, n(1), b);
      case 'explore':
        return (q['offset'] ?? 0) == 0 ? _experiences() : [];
      case 'experiences':
        final id = n(1);
        if (id != null && s.length > 2 && s[2] == 'like') {
          liked.contains(id) ? liked.remove(id) : liked.add(id);
          return {'liked': liked.contains(id), 'like_count': 12 + id % 30 + (liked.contains(id) ? 1 : 0)};
        }
        return {'id': nextId};
      case 'conversations':
        return _conversations(m, n(1), s.length > 2 ? s[2] : '', b);
      case 'accessories':
        return _accessories(s.length > 1 ? s[1] : '', q);
      case 'legal':
        return {'message': 'Başvurunuz alındı (demo). Gerçek sürümde 48 saat içinde incelenir.'};
      case 'admin':
        return m == 'GET' ? [] : {};
      case 'ai':
        return _ai(m, s.sublist(1), b);
    }
    return null;
  }

  // ---------- katalog ----------

  Map<String, dynamic> _card(Map<String, dynamic> p) => {
        for (final k in [
          'id', 'name', 'brand', 'image', 'price', 'rating', 'ai_rating', 'rating_count', 'best_choice_score', //
          'fp_score', 'badges', 'is_chronic_free', 'ar_type', 'category_id',
        ])
          k: p[k],
      };

  List<Map<String, dynamic>> _byCat(int c) => products.values.where((p) => p['category_id'] == c).toList();

  Map<String, dynamic> _home() {
    final all = products.values.where((p) => (p['category_id'] as int) < 10).toList();
    List<Map<String, dynamic>> withBadge(String b) => all.where((p) => (p['badges'] as List).contains(b)).map(_card).toList();
    return {
      'for_you': [for (final i in [3, 6, 1, 9, 12]) _card(products[i]!)],
      'showcases': [
        {'badge': 'En İyi Fiyat', 'products': withBadge('En İyi Fiyat')},
        {'badge': 'En Güvenilir', 'products': withBadge('En Güvenilir')},
        {'badge': 'Öğrenciler İçin İdeal', 'products': withBadge('Öğrenciler İçin İdeal')},
      ],
      'sections': [
        for (final c in _categories.where((c) => c['is_accessory'] == false))
          {
            'category': {'id': c['id'], 'name': c['name']},
            'products': (_byCat(c['id'] as int)..sort((a, b) => (b['best_choice_score'] as int) - (a['best_choice_score'] as int)))
                .map(_card)
                .toList(),
          },
      ],
    };
  }

  Map<String, dynamic> _facets(int catId) {
    final c = _categories.firstWhere((c) => c['id'] == catId, orElse: () => _categories.first);
    final items = _byCat(catId);
    final prices = items.map((p) => p['price'] as int).toList();
    return {
      'price': {
        'min': prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b),
        'max': prices.isEmpty ? 0 : prices.reduce((a, b) => a > b ? a : b),
      },
      'specs': [
        for (final f in c['spec_schema'] as List)
          {
            ...f as Map<String, dynamic>,
            if (f['type'] == 'number') ...() {
              final v = items.map((p) => (p['specs'] as Map)[f['key']]).whereType<num>().toList();
              return {
                'min': v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b),
                'max': v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b),
              };
            }(),
            if (f['type'] == 'enum')
              'options': items.map((p) => (p['specs'] as Map)[f['key']]).whereType<String>().toSet().toList(),
          },
      ],
    };
  }

  List<Map<String, dynamic>> _search(Map<String, dynamic> q) {
    final cat = int.tryParse('${q['category_id'] ?? ''}');
    final text = (q['q'] ?? '').toString().toLowerCase().trim();
    final badge = q['badge'] as String?;
    final minP = num.tryParse('${q['min_price'] ?? ''}');
    final maxP = num.tryParse('${q['max_price'] ?? ''}');
    var list = products.values.where((p) {
      if (cat != null && p['category_id'] != cat) return false;
      if (text.isNotEmpty && !'${p['name']} ${p['brand']}'.toLowerCase().contains(text)) return false;
      if (badge != null && !(p['badges'] as List).contains(badge)) return false;
      if (minP != null && (p['price'] as num) < minP) return false;
      if (maxP != null && (p['price'] as num) > maxP) return false;
      return true;
    }).toList();
    num key(Map p) => switch (q['sort']) {
          'cheapest' => p['price'],
          'expensive' => -(p['price'] as num),
          'fp' => -(p['fp_score'] as num),
          'rating' => -(p['rating'] as num),
          'popular' => -(p['rating_count'] as num),
          _ => -(p['best_choice_score'] as num),
        };
    list.sort((a, b) => key(a).compareTo(key(b)));
    return list.map(_card).toList();
  }

  Map<String, dynamic> _offerList(Map<String, dynamic> p) {
    final id = p['id'] as int;
    final base = p['price'] as int;
    final offers = <Map<String, dynamic>>[];
    for (var i = 0; i < _sellers.length; i++) {
      if ((id + i) % 4 == 3 && i > 1) continue;
      final (seller, url) = _sellers[i];
      final price = i == 0 ? base : (base * (1 + ((id * 7 + i * 13) % 11) / 100)).round();
      offers.add({
        'seller': seller,
        'price': price,
        'url': '$url${Uri.encodeQueryComponent(p['name'] as String)}',
        'in_stock': (id + i) % 6 != 5,
        'trusted': i < 6,
      });
    }
    offers.sort((a, b) => (a['price'] as int) - (b['price'] as int));
    return {'offers': offers};
  }

  Map<String, dynamic> _detail(int id) {
    final p = products[id] ?? products[1]!;
    final c = _categories.firstWhere((c) => c['id'] == p['category_id']);
    final price = p['price'] as int;
    final chronic = _chronic[p['id']] ?? const [];
    final best = (p['best_choice_score'] as int).toDouble();
    return {
      ...p,
      ..._offerList(p),
      'spec_schema': c['spec_schema'],
      'badge_basis': _badgeBasis,
      'review_count': 18 + id * 3,
      'fake_reviews_removed': id % 3 == 0 ? 0 : 3 + id % 5,
      'price_stats': {'min': (price * .93).round(), 'avg': (price * 1.04).round(), 'trend': ['down', 'flat', 'up'][id % 3]},
      'score_breakdown': {
        'price': (p['fp_score'] as int) - 4,
        'reviews': ((p['rating'] as double) * 19).round(),
        'features': best + 2,
        'durability': chronic.isEmpty ? 88 : 58,
        'popularity': ((p['rating_count'] as int) / 250).clamp(30, 95).round(),
        'value': p['fp_score'],
      },
      'external_ratings': [
        {'source': 'Trendyol', 'rating': p['rating'], 'rating_count': p['rating_count']},
        {'source': 'Hepsiburada', 'rating': double.parse(((p['rating'] as double) - .1).toStringAsFixed(1)), 'rating_count': ((p['rating_count'] as int) * .6).round()},
        {'source': 'Amazon Türkiye', 'rating': double.parse(((p['rating'] as double) + .1).clamp(0, 5).toStringAsFixed(1)), 'rating_count': ((p['rating_count'] as int) * .2).round()},
      ],
      'chronic_issues': chronic,
      'frequent_complaints': [
        {'title': 'Kutudan şarj aleti çıkmıyor', 'share': .12},
        {'title': 'Kargo paketlemesi zayıf', 'share': .05},
      ],
      'disclaimer': _disclaimer,
    };
  }

  Map<String, dynamic> _history(int id) {
    final p = products[id] ?? products[1]!;
    final price = p['price'] as int;
    final now = DateTime.now();
    return {
      'prices': [
        for (var d = 90; d >= 0; d -= 3)
          {
            't': now.subtract(Duration(days: d)).toIso8601String(),
            'price': (price * (1 + .08 * ((d % 27) / 27) - (d < 12 ? .02 : 0) + ((d * id) % 7) / 200)).round(),
          },
      ],
      'ratings': [
        for (var mo = 11; mo >= 0; mo--)
          {
            't': DateTime(now.year, now.month - mo, 1).toIso8601String(),
            'ai_rating': double.parse(((p['rating'] as double) - .3 + (11 - mo) * .025).toStringAsFixed(2)),
          },
      ],
    };
  }

  List<Map<String, dynamic>> _experiences({int? productId}) {
    final ids = productId == null ? [3, 1, 6, 12, 10, 7, 2, 9] : [productId, productId, productId];
    final now = DateTime.now();
    return [
      for (var i = 0; i < ids.length; i++)
        () {
          final p = products[ids[i]]!;
          final eid = 500 + ids[i] * 10 + i;
          return {
            'id': eid,
            'user': _people[i % _people.length],
            'product': {'id': p['id'], 'name': p['name'], 'image': null},
            'rating': [5, 4, 4, 5, 3][i % 5],
            'text': _reviewTexts[(i + ids[i]) % _reviewTexts.length],
            'created_at': now.subtract(Duration(days: 2 + i * 5)).toIso8601String(),
            'media': [],
            'like_count': 12 + eid % 30 + (liked.contains(eid) ? 1 : 0),
            'liked': liked.contains(eid),
            'verified_purchase': i % 3 != 2,
            'suspicious': false,
          };
        }(),
    ];
  }

  List<Map<String, dynamic>> _alternatives(int id) {
    final p = products[id] ?? products[1]!;
    final price = p['price'] as int;
    final alts = products.values.where((o) => o['category_id'] == p['category_id'] && (o['price'] as int) < price).toList()
      ..sort((a, b) => (b['best_choice_score'] as int) - (a['best_choice_score'] as int));
    return [
      for (final a in alts.take(3))
        {
          ..._card(a),
          'saving': price - (a['price'] as int),
          'saving_pct': ((price - (a['price'] as int)) / price * 100).round(),
          'similarity': 70 + (a['id'] as int) * 3 % 25,
          'differences': _diff(p, a),
        },
    ];
  }

  List<String> _diff(Map p, Map a) {
    final out = <String>[];
    final ps = p['specs'] as Map, alt = a['specs'] as Map;
    for (final k in ps.keys) {
      if (alt[k] != null && alt[k] != ps[k] && out.length < 3) out.add('$k: ${ps[k]} → ${alt[k]}');
    }
    return out;
  }

  List<Map<String, dynamic>> _seedQuestions(int id) => [
        {
          'id': 9000 + id * 10,
          'text': 'Kutudan şarj aleti çıkıyor mu?',
          'user': _people[0],
          'answers': <Map<String, dynamic>>[
            {'id': 9500 + id * 10, 'text': 'Hayır, sadece kablo var. 25 W adaptörü ayrıca aldım.', 'user': _people[1], 'is_owner': true, 'helpful_count': 14},
          ],
        },
        {
          'id': 9001 + id * 10,
          'text': 'Uzun süre kullananlar ısınma sorunu yaşıyor mu?',
          'user': _people[2],
          'answers': <Map<String, dynamic>>[
            {'id': 9501 + id * 10, 'text': '8 aydır kullanıyorum, oyunda biraz ısınıyor ama normal kullanımda sorun yok.', 'user': _people[3], 'is_owner': true, 'helpful_count': 9},
          ],
        },
      ];

  // ---------- sepet ----------

  Object _cart(String m, int? itemId, Map<String, dynamic> b) {
    if (m == 'POST') {
      final pid = b['product_id'] as int?;
      final existing = cart.where((i) => i['product_id'] == pid && i['project_title'] == null);
      if (existing.isNotEmpty) {
        existing.first['quantity'] = (existing.first['quantity'] as int) + 1;
      } else if (pid != null && products[pid] != null) {
        cart.add({'id': nextId, 'product_id': pid, 'quantity': 1, 'note': null, 'project_title': null});
      }
      return {};
    }
    if (m == 'PATCH') {
      for (final i in cart) {
        if (i['id'] == itemId) i['quantity'] = b['quantity'];
      }
      return {};
    }
    if (m == 'DELETE') {
      cart.removeWhere((i) => i['id'] == itemId);
      return {};
    }
    final items = [
      for (final i in cart) {...i, 'product': _card(products[i['product_id']]!)},
    ];
    final total = items.fold<int>(0, (s, i) => s + (i['product']['price'] as int) * (i['quantity'] as int));
    return {'items': items, 'total': total};
  }

  // ---------- mesajlar ----------

  Object _conversations(String m, int? id, String sub, Map<String, dynamic> b) {
    final now = DateTime.now();
    if (id == null) {
      if (m == 'POST') return {'id': 2};
      return [
        for (final c in [(1, _people[1], 'Kılıfı nereden aldın?', 1), (2, _people[0], 'Teşekkürler, çok yardımcı oldun!', 0)])
          {
            'id': c.$1,
            'other': {...c.$2, 'online': c.$1 == 1},
            'last_message': {'text': (messages[c.$1]?.last['text']) ?? c.$3, 'created_at': now.subtract(Duration(minutes: 15 * c.$1)).toIso8601String()},
            'unread': c.$4,
          },
      ];
    }
    final list = messages.putIfAbsent(
        id,
        () => [
              {'id': nextId, 'conversation_id': id, 'sender_id': 3, 'text': 'Merhaba, ürünü kaç aydır kullanıyorsun?', 'created_at': now.subtract(const Duration(hours: 2)).toIso8601String()},
              {'id': nextId, 'conversation_id': id, 'sender_id': 1, 'text': 'Selam, 6 aydır. Gayet memnunum.', 'created_at': now.subtract(const Duration(hours: 1)).toIso8601String()},
              {'id': nextId, 'conversation_id': id, 'sender_id': 3, 'text': 'Kılıfı nereden aldın?', 'created_at': now.subtract(const Duration(minutes: 15)).toIso8601String()},
            ]);
    if (m == 'POST' && sub == 'messages') {
      final msg = {'id': nextId, 'conversation_id': id, 'sender_id': 1, 'text': b['text'], 'created_at': now.toIso8601String()};
      list.add(msg);
      return msg;
    }
    return list;
  }

  // ---------- aksesuar ----------

  Object _accessories(String sub, Map<String, dynamic> q) {
    switch (sub) {
      case 'brands':
        return [
          {'id': 1, 'name': 'Samsung'},
          {'id': 2, 'name': 'Apple'},
          {'id': 3, 'name': 'Xiaomi'},
        ];
      case 'models':
        final brand = int.tryParse('${q['brand_id']}');
        return [
          for (final p in products.values)
            if (p['category_id'] == int.tryParse('${q['category_id']}') &&
                p['brand'] == const {1: 'Samsung', 2: 'Apple', 3: 'Xiaomi'}[brand])
              {'id': p['id'], 'name': p['name'], 'model_code': p['model_code']},
        ];
      case 'types':
        return [
          {'id': 10, 'name': 'Telefon Kılıfı'},
          {'id': 11, 'name': 'Şarj Aleti'},
        ];
      case 'compatible':
        final dev = products[int.tryParse('${q['device_id']}')] ?? products[1]!;
        final type = int.tryParse('${q['accessory_category_id']}');
        return {
          'device': {'id': dev['id'], 'name': dev['name']},
          'results': [
            for (final a in _byCat(type ?? 10))
              {
                ..._card(a),
                'compat': dev['id'] == 1 || type == 11 ? 'full' : 'partial',
                'compat_notes': dev['id'] == 1 || type == 11 ? [] : ['Kamera çıkıntısı tam oturmayabilir'],
              },
          ],
        };
    }
    return [];
  }

  // ---------- yapay zeka ----------

  Map<String, dynamic> _find(Object? query, [int fallback = 1]) {
    final t = (query ?? '').toString().toLowerCase();
    if (t.isNotEmpty) {
      for (final p in products.values) {
        final name = (p['name'] as String).toLowerCase();
        if (name.contains(t) || t.split(' ').where((w) => w.length > 2).every(name.contains)) return p;
      }
    }
    return products[fallback]!;
  }

  Map<String, dynamic> _verdict(Map<String, dynamic> p, {num? budget}) {
    final price = p['price'] as int;
    final over = budget != null && price > budget;
    final chronic = (_chronic[p['id']] ?? const []).isNotEmpty;
    final v = over || chronic ? 'BEKLE' : 'AL';
    return {
      'verdict': v,
      'verdict_label': v == 'AL' ? 'SATIN AL' : 'BEKLE',
      'fit_score': over ? 54 : (p['best_choice_score'] as int),
      'headline': v == 'AL'
          ? '${p['name']} ihtiyaçlarına uygun ve fiyatı son 90 günün ortalamasının altında.'
          : over
              ? 'Ürün bütçeni aşıyor; fiyat düşüşü beklemek veya alternatife bakmak mantıklı.'
              : 'Kullanıcıların bildirdiği tekrarlayan bir sorun var, karar vermeden önce incele.',
      'reasons': [
        'Kullanıcı puanı ${p['rating']} (${p['rating_count']} değerlendirme), sahte yorumlar ayıklandı.',
        'En düşük fiyat ${(price * .93).round()} TL, şu an $price TL.',
        if (chronic) 'Kronik sorun bildirimi var: ${(_chronic[p['id']]!.first)['title']}.',
        if (!chronic) 'Kronik sorun tespit edilmedi.',
      ],
      'suggestion': v == 'AL' ? 'En ucuz güvenilir satıcıdan almanı öneririz.' : 'Fiyat alarmı kur, 2-3 hafta içinde tekrar bak.',
      'disclaimer': _disclaimer,
    };
  }

  Map<String, dynamic> _mediaResult(Map<String, dynamic> p) => {
        'detected': {'full_name': p['name'], 'brand': p['brand'], 'confidence': .91},
        'product': _card(p),
        'fake_reviews_removed': 4,
        'price_stats': {'min': ((p['price'] as int) * .93).round(), 'avg': ((p['price'] as int) * 1.04).round()},
        'verdict': _verdict(p),
        'alternatives': _alternatives(p['id'] as int),
      };

  Object? _ai(String m, List<String> s, Map<String, dynamic> b) {
    final head = s.isEmpty ? '' : s[0];
    switch (head) {
      case 'duel':
        final a = b['a_id'] != null ? products[b['a_id']]! : _find(b['a_query'], 2);
        var bb = _find(b['b_query'], 1);
        if (bb['id'] == a['id']) bb = products[a['id'] == 1 ? 2 : 1]!;
        return _duel(a, bb);
      case 'should-buy':
        final p = b['product_id'] != null ? products[b['product_id']]! : _find(b['product_query']);
        return {
          'product': _card(p),
          ..._verdict(p, budget: b['budget'] as num?),
          'signals': {'alternatives': _alternatives(p['id'] as int)},
        };
      case 'mission':
        final text = (b['text'] ?? '').toString().toLowerCase();
        final cat = text.contains('kulak') ? 2 : text.contains('laptop') || text.contains('bilgisayar') ? 3 : text.contains('telefon') ? 1 : 2;
        final top = _byCat(cat)..sort((x, y) => (y['best_choice_score'] as int) - (x['best_choice_score'] as int));
        const strengths = ['En dengeli seçim', 'En iyi fiyat/performans', 'En uzun pil ömrü'];
        return {
          'compared': 40 + top.length * 6,
          'top3': [for (var i = 0; i < top.length && i < 3; i++) {..._card(top[i]), 'strength': strengths[i]}],
          'summary': 'Fiyat, sahte yorumlardan arındırılmış puan ve kronik sorun verisine göre sıraladım. (Demo verisi)',
        };
      case 'project':
        final picks = [(9, 'Laptop', 'Günlük çalışma için hafif ve güçlü'), (7, 'Kulaklık', 'Toplantılar için'), (21, 'Şarj adaptörü', null)];
        final items = [
          for (final (id, name, why) in picks) {'product': _card(products[id]!), 'item': {'name': name, 'quantity': 1, 'why': why}},
        ];
        if (b['add_to_cart'] == true) {
          for (final (id, name, _) in picks) {
            cart.add({'id': nextId, 'product_id': id, 'quantity': 1, 'note': name, 'project_title': b['title']});
          }
        }
        final total = picks.fold<int>(0, (t, e) => t + (products[e.$1]!['price'] as int));
        final budget = b['budget'] as num?;
        return {
          'total': total,
          'budget': budget,
          'over_budget': budget != null && total > budget,
          'items': items,
          'missing': ['Ergonomik sandalye'],
          'tips': ['Monitör kolu ile masada yer kazanabilirsin.'],
        };
      case 'sessions':
        if (s.length > 2 && s[2] == 'chat') return _chat((b['text'] ?? '').toString());
        return {'id': 1};
      case 'photo-search':
        return _mediaResult(products[3]!);
      case 'video':
        if (s.length > 1 && int.tryParse(s[1]) != null) {
          return {'id': int.parse(s[1]), 'status': 'done', 'stage': 'Tamamlandı', 'result': _mediaResult(products[6]!)};
        }
        return {'job_id': 1};
    }
    return {};
  }

  Map<String, dynamic> _duel(Map<String, dynamic> a, Map<String, dynamic> b) {
    final rounds = <Map<String, dynamic>>[];
    void add(String label, num? x, num? y, String unit, {bool lowerWins = false}) {
      if (x == null || y == null) return;
      final w = x == y ? 'tie' : ((x < y) == lowerWins ? 'a' : 'b');
      rounds.add({'label': label, 'a': x, 'b': y, 'unit': unit, 'winner': w});
    }

    add('Fiyat', a['price'], b['price'], ' ₺', lowerWins: true);
    final sa = a['specs'] as Map, sb = b['specs'] as Map;
    final schema = _categories.firstWhere((c) => c['id'] == a['category_id'])['spec_schema'] as List;
    for (final f in schema) {
      if (f['type'] == 'number') add(f['label'] as String, sa[f['key']] as num?, sb[f['key']] as num?, f['unit'] as String);
      if (f['type'] == 'bool' && sa[f['key']] != null && sb[f['key']] != null) {
        final x = sa[f['key']] == true, y = sb[f['key']] == true;
        rounds.add({'label': f['label'], 'a': x ? 'Var' : 'Yok', 'b': y ? 'Var' : 'Yok', 'unit': '', 'winner': x == y ? 'tie' : (x ? 'a' : 'b')});
      }
    }
    add('Kullanıcı puanı', a['rating'], b['rating'], '');
    add('Kronik sorun sayısı', (_chronic[a['id']] ?? const []).length, (_chronic[b['id']] ?? const []).length, '', lowerWins: true);
    add('Sahte yorum oranı', 3 + (a['id'] as int) % 5, 3 + (b['id'] as int) % 5, '%', lowerWins: true);
    add('90g en düşük fiyat', ((a['price'] as int) * .93).round(), ((b['price'] as int) * .93).round(), ' ₺', lowerWins: true);
    final sA = rounds.where((r) => r['winner'] == 'a').length, sB = rounds.where((r) => r['winner'] == 'b').length;
    final winner = sA >= sB ? a : b;
    return {
      'a': _card(a),
      'b': _card(b),
      'score': {'a': sA, 'b': sB},
      'overall_winner': sA >= sB ? 'a' : 'b',
      'rounds': rounds,
      'commentary': '${winner['name']} turların çoğunu kazandı. Bütçen kısıtlıysa fiyat farkını, '
          'uzun vadeli kullanım için kronik sorun ve puan satırlarını önemse. (Demo verisi)',
    };
  }

  Map<String, dynamic> _chat(String text) {
    final t = text.toLowerCase();
    final cat = t.contains('laptop') ? 3 : t.contains('kulak') ? 2 : t.contains('telefon') || t.contains('pil') ? 1 : 2;
    final picks = _byCat(cat)..sort((x, y) => (y['best_choice_score'] as int) - (x['best_choice_score'] as int));
    final best = picks.first;
    return {
      'role': 'model',
      'text': 'İsteğine göre En İyi Seçim sıralamasında öne çıkan ürün: ${best['name']} (${best['price']} TL). '
          'Sahte yorumlar ayıklandıktan sonra puanı ${best['rating']}. Aşağıda alternatifleri de görebilirsin. (Demo yanıtı)',
      'data': {'cards': picks.take(3).map(_card).toList()},
    };
  }
}
