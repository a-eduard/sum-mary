import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Аудио хранится только на устройстве: documents/SamMari/recordings
class LocalFiles {
  static Future<Directory> dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'SamMari', 'recordings'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> newRecordingPath() async =>
      p.join((await dir()).path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');

  /// Копирует импортированный файл в папку приложения (чтобы работал плеер).
  static Future<File> importCopy(String src) async {
    final dst = p.join((await dir()).path, 'imp_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}');
    return File(src).copy(dst);
  }

  static bool exists(String? path) => path != null && File(path).existsSync();
}
