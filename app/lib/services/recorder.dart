import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'local_files.dart';

/// Запись с микрофона. На Android запускает foreground-сервис,
/// чтобы запись не прерывалась при выключенном экране.
class Recorder {
  static const _fg = MethodChannel('sammari/foreground');
  final _rec = AudioRecorder();
  String? _path;
  final _sw = Stopwatch();

  Duration get elapsed => _sw.elapsed;
  bool get isPaused => !_sw.isRunning && _path != null;

  Stream<Amplitude> amplitude() => _rec.onAmplitudeChanged(const Duration(milliseconds: 120));

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    if (Platform.isAndroid) {
      await Permission.notification.request();
      await _fg.invokeMethod('start');
    }
    _path = await LocalFiles.newRecordingPath();
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1),
      path: _path!,
    );
    _sw.start();
    return true;
  }

  Future<void> pause() async {
    await _rec.pause();
    _sw.stop();
  }

  Future<void> resume() async {
    await _rec.resume();
    _sw.start();
  }

  /// Возвращает путь к файлу и длительность в секундах.
  Future<(String, int)?> stop() async {
    final path = await _rec.stop();
    _sw.stop();
    if (Platform.isAndroid) await _fg.invokeMethod('stop');
    if (path == null) return null;
    return (path, _sw.elapsed.inSeconds);
  }

  Future<void> cancel() async {
    await _rec.cancel();
    _sw.stop();
    if (Platform.isAndroid) await _fg.invokeMethod('stop');
  }

  Future<void> dispose() => _rec.dispose();
}
