import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF5B3DF5); // Kıyaslio moru
  static const accent = Color(0xFF00C2A8);
  static const buy = Color(0xFF1DB954);
  static const dontBuy = Color(0xFFE5484D);
  static const wait = Color(0xFFF5A524);
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, brightness: b, secondary: AppColors.accent);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF7F7FB) : null,
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: const ChipThemeData(side: BorderSide.none),
  );
}

/// Güven rozeti renkleri ve ikonları
({Color color, IconData icon}) badgeStyle(String badge) {
  switch (badge) {
    case 'En İyi Fiyat':
      return (color: const Color(0xFF1DB954), icon: Icons.sell);
    case 'En Güvenilir':
      return (color: const Color(0xFF2F80ED), icon: Icons.verified);
    case 'Öğrenciler İçin İdeal':
      return (color: const Color(0xFF9B51E0), icon: Icons.school);
    case 'Yüksek Riskli':
      return (color: const Color(0xFFE5484D), icon: Icons.warning_amber);
    case 'Popüler Ama Aşırı Pahalı':
      return (color: const Color(0xFFF2994A), icon: Icons.trending_up);
    case 'Kroniksiz':
      return (color: const Color(0xFF00A884), icon: Icons.health_and_safety);
    case 'En İyi Seçim':
      return (color: AppColors.brand, icon: Icons.emoji_events);
    default:
      return (color: Colors.grey, icon: Icons.label);
  }
}

const categoryIcons = <String, IconData>{
  'smartphone': Icons.smartphone,
  'laptop': Icons.laptop,
  'headphones': Icons.headphones,
  'chair': Icons.chair,
  'checkroom': Icons.checkroom,
  'spa': Icons.spa,
  'sports_esports': Icons.sports_esports,
  'memory': Icons.memory,
  'storage': Icons.storage,
  'phone_android': Icons.phone_android,
  'category': Icons.category,
};
