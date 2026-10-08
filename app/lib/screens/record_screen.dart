import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../models.dart';
import '../modes.dart';
import '../services/device_storage.dart';
import '../services/local_files.dart';
import '../services/recorder.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/mari_orb.dart';
import 'home_screen.dart' show showModeSheet;
import 'recording_screen.dart';

/// Экран записи: шар Мари, таймер, метки «Фото доски», «Важно!», «Не понял».
class RecordScreen extends StatefulWidget {
  final String mode;
  final String? folderId;
  const RecordScreen({super.key, this.mode = 'meeting', this.folderId});
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _rec = Recorder();
  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  final _levels = List<double>.filled(9, .2, growable: true);
  final _marks = <Map<String, dynamic>>[];
  late String _mode = widget.mode;
  bool _started = false, _saving = false;

  int _count(String type) => _marks.where((m) => m['type'] == type).length;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Перед записью: хватит ли памяти. Если мало — предлагаем удалить аудио уже обработанных записей.
  Future<bool> _checkSpace() async {
    final free = await DeviceStorage.freeBytes();
    if (free == null || free > 400 * 1024 * 1024) return true;
    if (!mounted) return false;
    final hours = DeviceStorage.hoursLeft(free);
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Мало памяти на телефоне'),
        content: Text('Свободно ${DeviceStorage.fmt(free)} — это примерно '
            '${hours < 1 ? '${(hours * 60).round()} мин' : '${hours.toStringAsFixed(1)} ч'} записи.\n\n'
            'Можно удалить с телефона аудио уже обработанных записей: итоги, расшифровки и фото останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'go'), child: const Text('Записывать')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'clean'), child: const Text('Освободить место')),
        ],
      ),
    );
    if (choice == 'clean') {
      final recs = await Repo.recordings().first;
      final freed = await DeviceStorage.cleanup(recs, days: 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Освобождено ${DeviceStorage.fmt(freed)}')));
      }
    }
    return true;
  }

  int _tick = 0;

  /// Во время записи: если память почти кончилась — сохраняем то, что есть, а не теряем лекцию.
  Future<void> _watchSpace() async {
    if (++_tick % 30 != 0 || _saving) return;
    final free = await DeviceStorage.freeBytes();
    if (free != null && free < 40 * 1024 * 1024 && mounted && !_saving) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Память телефона заканчивается — Мари остановила и сохранила запись'), duration: Duration(seconds: 6)));
      await _stop();
    }
  }

  Future<void> _start() async {
    await _checkSpace();
    if (!mounted) return;
    final ok = await _rec.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет доступа к микрофону')));
        Navigator.pop(context);
      }
      return;
    }
    _ampSub = _rec.amplitude().listen((a) {
      final v = ((a.current + 55) / 55).clamp(0.08, 1.0).toDouble();
      setState(() {
        _levels.add(v);
        _levels.removeAt(0);
      });
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
      _watchSpace();
    });
    setState(() => _started = true);
  }

  void _mark(String type, {String? path}) {
    setState(() => _marks.add({'type': type, 't': _rec.elapsed.inSeconds, if (path != null) 'path': path}));
    final label = switch (type) { 'important' => 'Отметила как важное', 'unclear' => 'Объясню этот момент после записи', _ => 'Фото добавлено' };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(label), duration: const Duration(seconds: 1)));
  }

  Future<void> _photo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 1800);
    if (x == null || !mounted) return;
    final path = await LocalPhotos.savePhoto(x.path);
    if (mounted) _mark('photo', path: path);
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
          source: Platform.isWindows ? 'desktop' : 'mic', mode: _mode, folderId: widget.folderId, localPath: path,
          durationSec: dur, marks: _marks);
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
    final s = context.sm;
    final mode = modeById(_mode);
    final paused = _rec.isPaused;
    Widget markBtn(IconData icon, Color color, String label, int n, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Material(
              color: s.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: s.border)),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _started ? onTap : null,
                child: SizedBox(
                  height: 84,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: color, size: 26),
                    const SizedBox(height: 6),
                    Text(label, style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 13)),
                    if (n > 0) Text('$n', style: TextStyle(color: s.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -.25),
                child: Container(
                  width: 460,
                  height: 460,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.orbViolet.withValues(alpha: context.isDark ? .32 : .2),
                      AppColors.orbCyan.withValues(alpha: .1),
                      s.bg.withValues(alpha: 0),
                    ], stops: const [0, .4, .68]),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(children: [
                Row(children: [
                  IconButton.outlined(
                    tooltip: 'Свернуть',
                    onPressed: () async {
                      if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  const Spacer(),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: paused ? s.muted : s.danger, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(paused ? 'ПАУЗА' : 'REC',
                        style: TextStyle(color: paused ? s.muted : s.danger, fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                  const Spacer(),
                  const SizedBox(width: 48),
                ]),
                const SizedBox(height: 8),
                ActionChip(
                  avatar: Icon(mode.icon, size: 18, color: mode.color),
                  label: Text(folderById(widget.folderId) == null ? mode.label : '${mode.label} · ${folderById(widget.folderId)!.name}'),
                  onPressed: () => showModeSheet(context, onPick: (m) => setState(() => _mode = m)),
                ),
                const SizedBox(height: 6),
                Text(fmtDuration(_rec.elapsed.inSeconds),
                    style: display(44, color: s.text).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                Expanded(
                  child: Center(child: MariOrb(size: 210, level: paused ? null : _levels.last)),
                ),
                SizedBox(
                  height: 40,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < _levels.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 4,
                        height: 6 + 34 * (paused ? .1 : _levels[i]),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i.isEven ? AppColors.orbViolet : AppColors.orbCyan,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(paused ? 'Запись на паузе' : 'Мари слушает — экран можно выключить',
                    style: TextStyle(color: s.muted, fontSize: 14)),
                const SizedBox(height: 18),
                Row(children: [
                  markBtn(Icons.photo_camera_rounded, s.teal, 'Фото доски', _count('photo'), _photo),
                  markBtn(Icons.star_rounded, s.warn, 'Важно!', _count('important'), () => _mark('important')),
                  markBtn(Icons.help_outline_rounded, s.accentText, 'Не понял', _count('unclear'), () => _mark('unclear')),
                ]),
                const SizedBox(height: 12),
                if (_saving)
                  const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())
                else
                  Row(children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: OutlinedButton(
                        onPressed: _started ? _togglePause : null,
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
                        child: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 28, semanticLabel: paused ? 'Продолжить' : 'Пауза'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 64,
                        child: FilledButton.icon(
                          onPressed: _started ? _stop : null,
                          style: FilledButton.styleFrom(backgroundColor: s.invBg, foregroundColor: s.invText,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('Завершить'),
                        ),
                      ),
                    ),
                  ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
