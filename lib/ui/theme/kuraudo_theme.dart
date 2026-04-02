/// Kuraudo テーマ定義
/// 
/// Zero to Ship デザイン方針準拠:
/// - ダーク基調（ライトモード対応）
/// - アクセントカラー: グリーン (#22c55e)
/// - テック感のあるデザイン
library;

import 'package:flutter/material.dart';

class KuraudoTheme {
  // ── カラーパレット ──
  static const Color accent = Color(0xFF22C55E);
  static const Color accentDark = Color(0xFF16A34A);
  static const Color accentLight = Color(0xFF4ADE80);

  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // ── ダークテーマ ──
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Noto Sans JP',

    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accentDark,
      surface: Color(0xFF0A0A0B),
      surfaceContainerHighest: Color(0xFF1A1A1D),
      onSurface: Color(0xFFE4E4E7),
      onSurfaceVariant: Color(0xFFA1A1AA),
      error: danger,
      outline: Color(0xFF27272A),
      outlineVariant: Color(0xFF1E1E21),
    ),

    scaffoldBackgroundColor: const Color(0xFF0A0A0B),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0A0B),
      foregroundColor: Color(0xFFE4E4E7),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Noto Sans JP',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFFE4E4E7),
      ),
    ),

    cardTheme: CardThemeData(
      color: const Color(0xFF111113),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1E1E21), width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF111113),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF27272A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF27272A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 14),
      labelStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Noto Sans JP',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: const BorderSide(color: Color(0xFF27272A)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 4,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1A1A1D),
      contentTextStyle: const TextStyle(color: Color(0xFFE4E4E7)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF111113),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Noto Sans JP',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFFE4E4E7),
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF0A0A0B),
      selectedItemColor: accent,
      unselectedItemColor: Color(0xFF52525B),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0xFF1E1E21),
      thickness: 1,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF1A1A1D),
      selectedColor: accent.withValues(alpha: 0.2),
      side: const BorderSide(color: Color(0xFF27272A)),
      labelStyle: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),

    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStateProperty.all(const Color(0xFF111113)),
      elevation: WidgetStateProperty.all(0),
      side: WidgetStateProperty.all(
        const BorderSide(color: Color(0xFF27272A)),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  // ── ライトテーマ ──
  static ThemeData get light => ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    fontFamily: 'Noto Sans JP',

    colorScheme: const ColorScheme.light(
      primary: accentDark,
      secondary: accent,
      surface: Color(0xFFF8FAFB),
      surfaceContainerHighest: Color(0xFFFFFFFF),
      onSurface: Color(0xFF18181B),
      onSurfaceVariant: Color(0xFF52525B),
      error: danger,
      outline: Color(0xFFD4D4D8),
      outlineVariant: Color(0xFFE4E4E7),
    ),

    scaffoldBackgroundColor: const Color(0xFFF8FAFB),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF8FAFB),
      foregroundColor: Color(0xFF18181B),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Noto Sans JP',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF18181B),
      ),
    ),

    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accentDark, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
      labelStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 14),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentDark,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accentDark,
      foregroundColor: Colors.white,
    ),
  );
}
