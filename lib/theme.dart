import 'package:flutter/material.dart';

/// 理財島設計系統 — 色彩 token
/// 對應 Claude Design「理財島設計系統」專案。
class AppColors {
  static const cream = Color(0xFFF7F2DE); // 頁面背景
  static const cardBg = Color(0xFFFFFDF4); // 卡片
  static const yellow = Color(0xFFE9CD62); // 島嶼黃：點數卡、次要按鈕
  static const sage = Color(0xFF8FB99F); // 緞帶綠
  static const mint = Color(0xFFCFE2CF); // 淺薄荷：標籤、分隔區
  static const teal = Color(0xFF3D7F7C); // 成功
  static const tealDark = Color(0xFF2E5F66); // 標題、主按鈕、AppBar
  static const brown = Color(0xFF7A4A33); // 黃底上的文字
  static const paper = Color(0xFFC08A5A); // 藏寶紙
  static const red = Color(0xFFA63B32); // 警示、錯誤
  static const sky = Color(0xFFBFE3EA); // 資訊標籤
  static const ink = Color(0xFF2E4A4E); // 內文
  static const muted = Color(0xFF6E7F76); // 次要文字
  static const line = Color(0xFFE5DBBB); // 卡片邊框
}

ThemeData buildIslandTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.tealDark,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.tealDark,
    secondary: AppColors.yellow,
    surface: AppColors.cream,
    error: AppColors.red,
    onSurface: AppColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Huninn',
    scaffoldBackgroundColor: AppColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.tealDark,
      foregroundColor: Color(0xFFF2F7F2),
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.tealDark,
        foregroundColor: const Color(0xFFF2F7F2),
        shape: const StadiumBorder(),
        minimumSize: const Size(44, 44),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.brown,
        elevation: 0,
        shape: const StadiumBorder(),
        minimumSize: const Size(44, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.tealDark,
        side: const BorderSide(color: AppColors.tealDark, width: 2),
        shape: const StadiumBorder(),
        minimumSize: const Size(44, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8CBA6), width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD8CBA6), width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.teal, width: 2),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.tealDark,
      contentTextStyle: TextStyle(fontFamily: 'Huninn', color: Color(0xFFF2F7F2)),
    ),
  );
}
