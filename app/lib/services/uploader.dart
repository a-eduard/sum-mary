import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'local_files.dart';
import 'repo.dart';

/// Состояние загрузки одной записи.
class UploadState {
  final double progress; // 0..1
  final String? error; // текст ошибки, если загрузка остановилась
  const UploadState(this.progress, [this.error]);
}

/// Загрузка аудио на сервер по протоколу TUS: кусками по 6 МБ, с процентами
/// и докачкой после обрыва связи или перезапуска приложения.
class Uploader {
  static final state = ValueNotifier<Map<String, UploadState>>({});
  static final _running = <String>{};
  static const _chunk = 6 * 1024 * 1024; // Supabase требует ровно 6 МБ на кусок
  static String get _base => '${AppConfig.supabaseUrl}/storage/v1/upload/resumable';

  static void _set(String id, UploadState s) => state.value = {...state.value, id: s};
  static void _clear(String id) => state.value = Map.of(state.value)..remove(id);

  static Map<String, String> _headers() => {
        'authorization': 'Bearer ${sb.auth.currentSession?.accessToken}',
        'apikey': AppConfig.supabaseAnonKey,
        'tus-resumable': '1.0.0',
      };

  /// Запускает (или продолжает) загрузку. Безопасно вызывать повторно.
  static Future<void> start(String recordingId, String path) async {
    if (_running.contains(recordingId)) return;
    _running.add(recordingId);
    try {
      for (var attempt = 0;; attempt++) {
        try {
          await _upload(recordingId, File(path));
          _clear(recordingId);
          return;
        } catch (e) {
          if (attempt >= 4) {
            _set(recordingId, UploadState(state.value[recordingId]?.progress ?? 0, _human(e)));
            return;
          }
          await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
          try {
            await sb.auth.refreshSession();
          } catch (_) {}
        }
      }
    } finally {
      _running.remove(recordingId);
    }
  }

  /// После запуска приложения: докачать всё, что не успело загрузиться.
  static Future<void> resumePending(List<dynamic> recordings) async {
    for (final r in recordings) {
      if (r.status == 'uploading' && LocalFiles.exists(r.localAudio)) {
        unawaited(start(r.id, r.localAudio!));
      }
    }
  }

  static String _human(Object e) {
    final s = '$e';
    if (s.contains('SocketException') || s.contains('Timeout') || s.contains('Connection')) {
      return 'Нет связи — загрузка продолжится, когда появится интернет';
    }
    if (s.contains('413') || s.contains('too large')) return 'Файл слишком большой (больше 1 ГБ)';
    return 'Не удалось загрузить: $s';
  }

  static Future<void> _upload(String recordingId, File file) async {
    final total = await file.length();
    final ext = p.extension(file.path).isEmpty ? '.m4a' : p.extension(file.path).toLowerCase();
    final object = '${Repo.uid}/$recordingId$ext';
    final prefs = await SharedPreferences.getInstance();
    final key = 'tus_$recordingId';
    var url = prefs.getString(key);
    var offset = 0;

    if (url != null) {
      final h = await http.head(Uri.parse(url), headers: _headers()).timeout(const Duration(seconds: 30));
      if (h.statusCode == 200 || h.statusCode == 204) {
        offset = int.tryParse(h.headers['upload-offset'] ?? '') ?? 0;
      } else {
        url = null;
      }
    }
    if (url == null) {
      String b64(String v) => base64.encode(utf8.encode(v));
      final r = await http.post(Uri.parse(_base), headers: {
        ..._headers(),
        'upload-length': '$total',
        'x-upsert': 'true',
        'upload-metadata': [
          'bucketName ${b64('audio')}',
          'objectName ${b64(object)}',
          'contentType ${b64(_mime(ext))}',
          'cacheControl ${b64('3600')}',
        ].join(','),
      }).timeout(const Duration(seconds: 30));
      if (r.statusCode != 201) throw Exception('создание загрузки: ${r.statusCode} ${r.body}');
      final loc = r.headers['location'] ?? '';
      // Сервер за прокси может вернуть внутренний адрес — берём только идентификатор загрузки.
      url = '$_base/${Uri.parse(loc).pathSegments.last}';
      await prefs.setString(key, url);
    }

    final raf = await file.open();
    try {
      while (offset < total) {
        _set(recordingId, UploadState(offset / total));
        final len = math.min(_chunk, total - offset);
        await raf.setPosition(offset);
        final bytes = await raf.read(len);
        final r = await http
            .patch(Uri.parse(url), headers: {
              ..._headers(),
              'upload-offset': '$offset',
              'content-type': 'application/offset+octet-stream',
            }, body: bytes)
            .timeout(const Duration(minutes: 3));
        if (r.statusCode == 409) {
          // смещение разошлось — спрашиваем у сервера, сколько уже принято
          final h = await http.head(Uri.parse(url), headers: _headers());
          offset = int.tryParse(h.headers['upload-offset'] ?? '') ?? offset;
          continue;
        }
        if (r.statusCode != 204) throw Exception('кусок: ${r.statusCode} ${r.body}');
        offset = int.tryParse(r.headers['upload-offset'] ?? '') ?? offset + len;
      }
    } finally {
      await raf.close();
    }
    _set(recordingId, const UploadState(1));
    // Фото доски — до постановки в очередь, чтобы Мари учла их в конспекте.
    try {
      await Repo.uploadPhotos(recordingId);
    } catch (_) {}
    await sb.from('recordings').update({'audio_path': object, 'status': 'queued'}).eq('id', recordingId);
    await prefs.remove(key);
  }

  static String _mime(String ext) => switch (ext) {
        '.mp3' => 'audio/mpeg',
        '.wav' => 'audio/wav',
        '.ogg' || '.oga' || '.opus' => 'audio/ogg',
        '.aac' => 'audio/aac',
        '.flac' => 'audio/flac',
        '.mp4' || '.m4a' => 'audio/mp4',
        '.webm' => 'audio/webm',
        _ => 'application/octet-stream',
      };
}
