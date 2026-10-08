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
        .timeout(const Duration(minutes: 5));
    final data = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) {
      throw Exception(data is Map && data['detail'] != null ? data['detail'] : 'Ошибка сервера ${r.statusCode}');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Чат с Мари: по записи, по полке или (без обоих) по всем записям.
  static Future<String> chat(String question, List<Map<String, String>> history, {String? recordingId, String? folderId}) async {
    final d = await _post('/chat', {
      if (recordingId != null) 'recording_id': recordingId,
      if (folderId != null) 'folder_id': folderId,
      'question': question,
      'history': history,
    });
    return d['answer'] as String;
  }

  /// Подготовка: kind = quiz | cards | tickets.
  static Future<List<Map<String, dynamic>>> prepare(String kind,
      {String? recordingId, String? folderId, String tickets = '', int count = 10}) async {
    final d = await _post('/prepare', {
      'kind': kind,
      if (recordingId != null) 'recording_id': recordingId,
      if (folderId != null) 'folder_id': folderId,
      'tickets': tickets,
      'count': count,
    });
    return List<Map<String, dynamic>>.from((d['items'] as List).map((e) => Map<String, dynamic>.from(e)));
  }

  /// Пересобрать итог в другом режиме (без повторной расшифровки).
  static Future<void> resummarize(String recordingId, String mode) =>
      _post('/resummarize', {'recording_id': recordingId, 'mode': mode});

  /// Сообщение в поддержку: сервер сохраняет его и пересылает владельцу в Telegram.
  static Future<void> support(String text, {String? appVersion, String? device}) =>
      _post('/support', {'text': text, 'app_version': appVersion, 'device': device});

  static Future<void> confirmPurchase(String purchaseId, String productId, {bool sandbox = false}) =>
      _post('/billing/rustore', {'purchase_id': purchaseId, 'product_id': productId, 'sandbox': sandbox});
}
