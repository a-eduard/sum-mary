/// Настройки приложения. Значения можно переопределить при сборке:
/// flutter run --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://db.sum-mary.ru');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'ВСТАВЬТЕ_ANON_KEY');
  static const apiUrl =
      String.fromEnvironment('API_URL', defaultValue: 'https://api.sum-mary.ru');

  /// ID подписки в консоли RuStore
  static const proProductId = 'sammari_pro_month';
  static const privacyUrl = 'https://sum-mary.ru/privacy';
  static const termsUrl = 'https://sum-mary.ru/terms';
}
