import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../models.dart';
import '../services/recorder.dart';
import '../services/repo.dart';
import '../theme.dart';
import 'recording_screen.dart';

/// Экран записи: таймер, «волна» громкости, пауза, стоп.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _rec = Recorder();
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  final _levels = <double>[];
  bool _started = false, _saving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ok = await _rec.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет доступа к микрофону')));
        Navigator.pop(context);
      }
      return;
    }
    _ampSub = _rec.amplitude().listen((a) {
      final v = ((a.current + 60) / 60).clamp(0.05, 1.0);
      setState(() {
        _levels.add(v);
        if (_levels.length > 60) _levels.removeAt(0);
      });
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() => _started = true);
  }

  Future<void> _togglePause() async {
    _rec.isPaused ? await _rec.resume() : await _rec.pause();
    setState(() {});
  }

  Future<void> _stop() async {
    setState(() => _saving = true);
    _timer?.cancel();
    await _ampSub?.cancel();
    final res = await _rec.stop();
    if (res == null || !mounted) return;
    final (path, dur) = res;
    try {
      final id = await Repo.createRecording(
          source: Platform.isWindows ? 'desktop' : 'mic', localPath: path, durationSec: dur);
      Repo.uploadAndQueue(id, File(path)).catchError((_) {});
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: id)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Не удалось отправить запись: $e. Файл сохранён на устройстве.')));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_started) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: const Text('Запись будет остановлена и не сохранится.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Продолжить запись')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      _timer?.cancel();
      await _ampSub?.cancel();
      await _rec.cancel();
    }
    return ok == true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Запись')),
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 24),
            Text(_rec.isPaused ? 'Пауза' : 'Мари слушает…',
                style: const TextStyle(fontSize: 18, color: AppColors.muted)),
            const SizedBox(height: 12),
            Text(fmtDuration(_rec.elapsed.inSeconds),
                style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 32),
            SizedBox(
              height: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final l in _levels)
                    Container(
                      width: 4,
                      height: 120 * l,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                    ),
                ],
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text('Можно заблокировать экран — запись продолжится. Не забудьте предупредить собеседников о записи.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
            const SizedBox(height: 24),
            if (_saving)
              const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton.filledTonal(
                  iconSize: 32,
                  onPressed: _started ? _togglePause : null,
                  icon: Icon(_rec.isPaused ? Icons.play_arrow : Icons.pause),
                ),
                SizedBox(
                  width: 88,
                  height: 88,
                  child: FloatingActionButton(
                    heroTag: 'stop',
                    backgroundColor: AppColors.record,
                    shape: const CircleBorder(),
                    onPressed: _started ? _stop : null,
                    child: const Icon(Icons.stop, size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 56),
              ]),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}
