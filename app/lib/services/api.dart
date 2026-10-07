import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'repo.dart';

/// Наш сервер api.sum-mary.ru (чат с Мари, подтверждение покупок).
class Api {
  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final token = sb.auth.currentSession?.accessToken;
    final r = await http
        .post(Uri.parse('${AppConfig.apiUrl}$path'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
            body: jsonEncode(body))
        .timeout(const Duration(minutes: 3));
    final data = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) {
      throw Exception(data is Map && data['detail'] != null ? data['detail'] : 'Ошибка сервера ${r.statusCode}');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<String> chat(String recordingId, String question, List<Map<String, String>> history) async {
    final d = await _post('/chat', {'recording_id': recordingId, 'question': question, 'history': history});
    return d['answer'] as String;
  }

  /// Пересобрать итог в другом режиме (без повторной расшифровки).
  static Future<void> resummarize(String recordingId, String mode) =>
      _post('/resummarize', {'recording_id': recordingId, 'mode': mode});

  static Future<void> confirmPurchase(String purchaseId, String productId, {bool sandbox = false}) =>
      _post('/billing/rustore', {'purchase_id': purchaseId, 'product_id': productId, 'sandbox': sandbox});
}
