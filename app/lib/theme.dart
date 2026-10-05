import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0F1015);
  static const card = Color(0xFF1A1C24);
  static const accent = Color(0xFF7C6CF2); // фиолетовый Мари
  static const record = Color(0xFFFF4D6D); // кнопка записи
  static const muted = Color(0xFF9AA0B4);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.bg,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    cardTheme: const CardThemeData(
      color: AppColors.card,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, centerTitle: false),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
    ),
  );
}
