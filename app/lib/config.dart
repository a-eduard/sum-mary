/// Настройки приложения. Значения можно переопределить при сборке:
/// flutter run --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://db.sum-mary.ru');
  static const supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzkxMjMzMTA5LCJleHAiOjE5NDg5MTMxMDl9.sik8B8EXZit92K18D26bVK87GXqyVkbBEHjEvB2NtR4');
  static const apiUrl =
      String.fromEnvironment('API_URL', defaultValue: 'https://api.sum-mary.ru');

  /// ID подписки в консоли RuStore
  static const proProductId = 'sammari_pro_month';
  static const privacyUrl = 'https://sum-mary.ru/privacy';
  static const termsUrl = 'https://sum-mary.ru/terms';
}
