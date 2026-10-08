import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'local_files.dart';

/// Память телефона: свободное место, объём записей и автоочистка старого аудио.
/// Итоги, расшифровки и фото доски хранятся на сервере — удаляется только аудиофайл на телефоне.
class DeviceStorage {
  static const _ch = MethodChannel('sammari/storage');
  static const _keepKey = 'audio_keep_days';

  /// Запись идёт в AAC 32 кбит/с моно ≈ 14,4 МБ в час (+ запас).
  static const bytesPerHour = 15 * 1024 * 1024;

  /// Сколько дней хранить аудио обработанных записей: 7, 30, 90 или -1 (всегда).
  static final keepDays = ValueNotifier<int>(30);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    keepDays.value = p.getInt(_keepKey) ?? 30;
  }

  static Future<void> setKeepDays(int days) async {
    keepDays.value = days;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keepKey, days);
  }

  static Future<int?> freeBytes() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<int>('freeBytes');
    } catch (_) {
      return null;
    }
  }

  /// Хватит ли места: часы записи при текущем свободном месте.
  static double hoursLeft(int free) => free / bytesPerHour;

  /// Сколько занимают аудио и фото в папке приложения.
  static Future<int> usedBytes() async {
    var sum = 0;
    try {
      await for (final f in (await LocalFiles.dir()).list()) {
        if (f is File) sum += await f.length();
      }
    } catch (_) {}
    return sum;
  }

  /// Удаляет аудио обработанных записей старше [days] дней (0 — все обработанные). Возвращает освобождённые байты.
  /// Фото удаляются только если уже загружены на сервер (есть key).
  static Future<int> cleanup(List<Recording> recs, {int? days}) async {
    final d = days ?? keepDays.value;
    if (d < 0) return 0;
    final border = DateTime.now().subtract(Duration(days: d));
    var freed = 0;
    for (final r in recs) {
      if (!r.isReady || r.recordedAt.isAfter(border)) continue;
      final paths = [
        r.localAudio,
        for (final m in r.marks)
          if (m['type'] == 'photo' && m['key'] != null) m['path'] as String?,
      ];
      for (final path in paths) {
        if (path == null) continue;
        final f = File(path);
        try {
          if (await f.exists()) {
            freed += await f.length();
            await f.delete();
          }
        } catch (_) {}
      }
    }
    return freed;
  }

  static String fmt(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
    return '${(bytes / (1024 * 1024)).round()} МБ';
  }
}
