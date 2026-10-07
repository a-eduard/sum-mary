import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Цвета, не зависящие от темы.
class AppColors {
  static const record = Color(0xFFFF4D6D);
  // Шар Мари: бирюза → фиолетовый.
  static const orbLight = Color(0xFFE6FFFB);
  static const orbCyan = Color(0xFF4FD1C5);
  static const orbViolet = Color(0xFF8B7CFF);
  static const orbDeep = Color(0xFF2B2170);
}

/// Палитра «Ночной эфир» — светлая и тёмная версии.
@immutable
class Sm extends ThemeExtension<Sm> {
  final Color bg, card, border, text, muted, nav, accent, onAccent, accentText, chip, onChip;
  final Color heroStart, heroBorder, heroText, invBg, invText, danger, success, warn, teal;
  const Sm({
    required this.bg, required this.card, required this.border, required this.text, required this.muted,
    required this.nav, required this.accent, required this.onAccent, required this.accentText,
    required this.chip, required this.onChip, required this.heroStart, required this.heroBorder,
    required this.heroText, required this.invBg, required this.invText, required this.danger,
    required this.success, required this.warn, required this.teal,
  });

  static const dark = Sm(
    bg: Color(0xFF0F1015), card: Color(0xFF1A1C24), border: Color(0xFF2A2D3A), text: Color(0xFFF2F1EE),
    muted: Color(0xFF9A9DAB), nav: Color(0xD11A1C24), accent: Color(0xFF8B7CFF), onAccent: Color(0xFF0F1015),
    accentText: Color(0xFFB3A9FF), chip: Color(0xFF6EA8FF), onChip: Color(0xFF0F1015),
    heroStart: Color(0xFF2B2560), heroBorder: Color(0xFF3A3478), heroText: Color(0xFFC9C6E8),
    invBg: Color(0xFFF2F1EE), invText: Color(0xFF0F1015), danger: Color(0xFFFF7A90),
    success: Color(0xFF6FE0B0), warn: Color(0xFFFFB86B), teal: Color(0xFF4FD1C5),
  );

  static const light = Sm(
    bg: Color(0xFFF4F4F8), card: Color(0xFFFFFFFF), border: Color(0xFFE3E4EC), text: Color(0xFF14151B),
    muted: Color(0xFF5F6273), nav: Color(0xD1FFFFFF), accent: Color(0xFF5B4BDB), onAccent: Color(0xFFFFFFFF),
    accentText: Color(0xFF5B4BDB), chip: Color(0xFF2F6FEB), onChip: Color(0xFFFFFFFF),
    heroStart: Color(0xFFECE8FF), heroBorder: Color(0xFFD6CFFF), heroText: Color(0xFF4E4398),
    invBg: Color(0xFF14151B), invText: Color(0xFFFFFFFF), danger: Color(0xFFC0263F),
    success: Color(0xFF1F7A50), warn: Color(0xFFC2620F), teal: Color(0xFF0E8A80),
  );

  @override
  Sm copyWith() => this;
  @override
  Sm lerp(ThemeExtension<Sm>? other, double t) => (other is Sm && t > .5) ? other : this;
}

extension SmContext on BuildContext {
  Sm get sm => Theme.of(this).extension<Sm>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Заголовочный шрифт (Unbounded).
TextStyle display(double size, {Color? color, FontWeight weight = FontWeight.w700}) =>
    GoogleFonts.unbounded(fontSize: size, fontWeight: weight, color: color, height: 1.25);

ThemeData buildTheme(Brightness b) {
  final s = b == Brightness.dark ? Sm.dark : Sm.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: s.accent, brightness: b, surface: s.bg, primary: s.accent, onPrimary: s.onAccent),
    scaffoldBackgroundColor: s.bg,
    extensions: [s],
  );
  return base.copyWith(
    textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(bodyColor: s.text, displayColor: s.text),
    cardTheme: CardThemeData(
      color: s.card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: s.border)),
    ),
    appBarTheme: AppBarTheme(backgroundColor: s.bg, surfaceTintColor: Colors.transparent, centerTitle: false, foregroundColor: s.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.card,
      hintStyle: TextStyle(color: s.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: s.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: s.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: s.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: s.accent, foregroundColor: s.onAccent, minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: s.text, side: BorderSide(color: s.border), backgroundColor: s.card, minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: s.card, selectedColor: s.accent, side: BorderSide(color: s.border),
      labelStyle: TextStyle(color: s.text, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: s.onAccent, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      checkmarkColor: s.onAccent,
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: s.card, surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    dialogTheme: DialogThemeData(backgroundColor: s.card, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    dividerTheme: DividerThemeData(color: s.border),
    // Плавающие тосты в стиле приложения, над стеклянной панелью навигации.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.text,
      contentTextStyle: TextStyle(color: s.bg, fontSize: 15, fontWeight: FontWeight.w600),
      actionTextColor: s.accent,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Выбор темы: системная / светлая / тёмная (сохраняется на устройстве).
class ThemeController {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static const _key = 'theme_mode';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode.value = ThemeMode.values.firstWhere((m) => m.name == p.getString(_key), orElse: () => ThemeMode.system);
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    (await SharedPreferences.getInstance()).setString(_key, m.name);
  }
}
