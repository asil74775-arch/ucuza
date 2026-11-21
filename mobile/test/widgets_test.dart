import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ucuza/core/models.dart';
import 'package:ucuza/core/widgets.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  test('ProductCard JSON çözümleme', () {
    final p = ProductCard.fromJson({
      'id': 1, 'name': 'Test', 'price': 1499, 'ai_rating': 4.4, 'rating_count': 12,
      'best_choice_score': 81.5, 'fp_score': 70, 'badges': ['Kroniksiz'], 'is_chronic_free': true,
    });
    expect(p.price, 1499.0);
    expect(p.badges, contains('Kroniksiz'));
  });

  test('TL biçimlendirme', () => expect(tl(15999), contains('15.999')));

  testWidgets('Rozet ve yıldız bileşenleri', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [BadgeChip('Yüksek Riskli'), Stars(4.5, count: 10)])),
    ));
    expect(find.text('Yüksek Riskli'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
  });
}
