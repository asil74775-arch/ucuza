/// Hafif tipli modeller. Ayrıntılı ekranlar ham JSON (Map) üzerinden de çalışır.
class ProductCard {
  ProductCard.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'] ?? '',
        brand = j['brand'],
        image = j['image'],
        price = (j['price'] ?? 0).toDouble(),
        rating = (j['rating'] ?? 0).toDouble(),
        aiRating = (j['ai_rating'] ?? 0).toDouble(),
        ratingCount = j['rating_count'] ?? 0,
        bestChoice = (j['best_choice_score'] ?? 0).toDouble(),
        fp = (j['fp_score'] ?? 0).toDouble(),
        badges = List<String>.from(j['badges'] ?? const []),
        chronicFree = j['is_chronic_free'] ?? false,
        arType = j['ar_type'],
        raw = j;

  final int id;
  final String name;
  final String? brand;
  final String? image;
  final double price;
  final double rating;
  final double aiRating;
  final int ratingCount;
  final double bestChoice;
  final double fp;
  final List<String> badges;
  final bool chronicFree;
  final String? arType;
  final Map<String, dynamic> raw;

  static List<ProductCard> list(dynamic data) =>
      (data as List).map((e) => ProductCard.fromJson(Map<String, dynamic>.from(e))).toList();
}

class Category {
  Category.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        slug = j['slug'],
        name = j['name'],
        icon = j['icon'] ?? 'category',
        isAccessory = j['is_accessory'] ?? false,
        specSchema = List<Map<String, dynamic>>.from(
            (j['spec_schema'] ?? const []).map((e) => Map<String, dynamic>.from(e)));
  final int id;
  final String slug;
  final String name;
  final String icon;
  final bool isAccessory;
  final List<Map<String, dynamic>> specSchema;
}
