import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../modes.dart';
import '../services/local_files.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';
import '../widgets/recording_tile.dart';
import 'record_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _recordingsKey = GlobalKey<RecordingsPageState>();

  void _record([String mode = 'meeting']) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecordScreen(mode: mode)));

  void _openSearch() {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordingsKey.currentState?.focusSearch());
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(onRecord: _record, onAsk: _openSearch, onImportCall: () => importAudio(context, call: true)),
      RecordingsPage(key: _recordingsKey),
      const TasksScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: GlassNav(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
        onRecord: () => _record(),
        onRecordLong: () => showModeSheet(context, onPick: _record),
      ),
    );
  }
}

/// Плавающая нижняя панель «стекло» с шаром записи в центре.
class GlassNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onRecord, onRecordLong;
  const GlassNav({super.key, required this.index, required this.onTap, required this.onRecord, required this.onRecordLong});

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    Widget item(int i, IconData icon, String label) => Expanded(
          child: Semantics(
            selected: index == i,
            child: IconButton(
              tooltip: label,
              onPressed: () => onTap(i),
              icon: Icon(icon, size: 26, color: index == i ? s.text : s.muted),
            ),
          ),
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 96,
          child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: s.nav,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: s.border),
                  ),
                  child: Row(children: [
                    item(0, Icons.home_rounded, 'Сегодня'),
                    item(1, Icons.folder_rounded, 'Записи'),
                    const SizedBox(width: 80),
                    item(2, Icons.task_alt_rounded, 'Задачи'),
                    item(3, Icons.person_rounded, 'Профиль'),
                  ]),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Semantics(
                button: true,
                label: 'Начать запись',
                child: GestureDetector(
                  onTap: onRecord,
                  onLongPress: onRecordLong,
                  child: const MariOrb(size: 68, child: Icon(Icons.mic_rounded, size: 30, color: Color(0xFF0F1015))),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Выбор режима записи.
void showModeSheet(BuildContext context, {required void Function(String) onPick}) {
  final s = context.sm;
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Что записываем?', style: display(18, color: s.text)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in recModes)
              ActionChip(
                avatar: Icon(m.icon, size: 18, color: m.color),
                label: Text(m.label),
                onPressed: () {
                  Navigator.pop(context);
                  onPick(m.id);
                },
              ),
          ]),
        ]),
      ),
    ),
  );
}

/// Импорт аудиофайлов: записи звонков, диктофон, файлы из мессенджеров.
Future<void> importAudio(BuildContext context, {bool call = false}) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
  if (res == null) return;
  for (final f in res.files.where((f) => f.path != null)) {
    final copy = await LocalFiles.importCopy(f.path!);
    final id = await Repo.createRecording(
        source: call ? 'call' : 'import', mode: call ? 'call' : 'meeting', localPath: copy.path);
    Repo.uploadAndQueue(id, File(copy.path)).catchError((_) {});
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено файлов: ${res.files.length}. Мари уже обрабатывает их.')));
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Доброй ночи';
  if (h < 12) return 'Доброе утро';
  if (h < 18) return 'Добрый день';
  return 'Добрый вечер';
}

/// Главная «Сегодня»: приветствие, быстрые действия, ближайшие задачи, недавние записи.
class TodayPage extends StatefulWidget {
  final void Function(String mode) onRecord;
  final VoidCallback onAsk, onImportCall;
  const TodayPage({super.key, required this.onRecord, required this.onAsk, required this.onImportCall});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late final Stream<List<Recording>> _recs = Repo.recordings();
  late final Stream<List<TaskItem>> _tasks = Repo.tasks();

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final date = toBeginningOfSentenceCase(DateFormat('EEEE, d MMMM', 'ru').format(DateTime.now()));
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Text(t, style: display(13, color: s.muted, weight: FontWeight.w500)),
        );
    Widget quick(String label, VoidCallback onTap, {bool primary = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: primary
                ? FilledButton(onPressed: onTap, style: FilledButton.styleFrom(padding: EdgeInsets.zero), child: Text(label))
                : OutlinedButton(onPressed: onTap, style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), child: Text(label)),
          ),
        );

    return Stack(children: [
      Positioned(
        top: -120,
        right: -100,
        child: IgnorePointer(
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.orbViolet.withValues(alpha: context.isDark ? .35 : .22),
                AppColors.orbCyan.withValues(alpha: .10),
                s.bg.withValues(alpha: 0),
              ], stops: const [0, .45, .7]),
            ),
          ),
        ),
      ),
      ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 140), children: [
        Row(children: [
          const MariOrb(size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(date, style: TextStyle(color: s.muted, fontSize: 14)),
              const SizedBox(height: 4),
              Text(_greeting(), style: display(22, color: s.text)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Material(
          color: s.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: s.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onAsk,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, color: s.accentText, size: 20),
                const SizedBox(width: 10),
                Text('Спросить Мари о любой записи…', style: TextStyle(color: s.muted, fontSize: 15)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          quick('Урок', () => widget.onRecord('lesson'), primary: true),
          quick('Лекция', () => widget.onRecord('lecture')),
          quick('Встреча', () => widget.onRecord('meeting')),
          quick('Звонок', widget.onImportCall),
        ]),
        StreamBuilder<List<TaskItem>>(
          stream: _tasks,
          builder: (context, snap) {
            final open = (snap.data ?? []).where((t) => !t.done).take(3).toList();
            if (open.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              section('Ближайшее'),
              _HeroTask(task: open.first),
              for (final t in open.skip(1)) _TaskRow(task: t),
            ]);
          },
        ),
        StreamBuilder<List<Recording>>(
          stream: _recs,
          builder: (context, snap) {
            final list = (snap.data ?? []).take(3).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              section('Недавнее'),
              if (snap.hasError)
                Text('Нет связи с сервером', style: TextStyle(color: s.muted))
              else if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (list.isEmpty)
                Text('Здесь появятся ваши записи. Нажмите на шар внизу — Мари начнёт слушать.',
                    style: TextStyle(color: s.muted, height: 1.4))
              else
                for (final r in list)
                  RecordingTile(
                    r: r,
                    margin: const EdgeInsets.only(bottom: 10),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: r.id))),
                  ),
            ]);
          },
        ),
      ]),
    ]);
  }
}

class _HeroTask extends StatelessWidget {
  final TaskItem task;
  const _HeroTask({required this.task});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.heroBorder),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.heroStart, s.card], stops: const [0, .75]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (task.dueText != null) Text(task.dueText!, style: TextStyle(color: s.heroText, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(task.text, style: TextStyle(color: s.text, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton(
            onPressed: () => Repo.setTaskDone(task.id, true),
            style: FilledButton.styleFrom(backgroundColor: s.invBg, foregroundColor: s.invText, minimumSize: const Size(0, 44)),
            child: const Text('Готово'),
          ),
          if (task.recordingId != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: task.recordingId!))),
              child: Text('Открыть запись', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskItem task;
  const _TaskRow({required this.task});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.border)),
      child: Row(children: [
        IconButton(
          tooltip: 'Отметить выполненной',
          onPressed: () => Repo.setTaskDone(task.id, true),
          icon: Icon(Icons.radio_button_unchecked_rounded, color: s.teal, size: 28),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.text, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 15)),
            if (task.dueText != null) Text(task.dueText!, style: TextStyle(color: s.muted, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

/// Все записи: поиск, фильтры по режимам.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});
  @override
  State<RecordingsPage> createState() => RecordingsPageState();
}

class RecordingsPageState extends State<RecordingsPage> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  List<Recording>? _found;
  String _filter = 'all';
  late final Stream<List<Recording>> _stream = Repo.recordings();

  void focusSearch() => _focus.requestFocus();

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _found = null);
      return;
    }
    final r = await Repo.search(q.trim());
    if (mounted) setState(() => _found = r);
  }

  void _importMenu() {
    final s = context.sm;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Icon(Icons.call_rounded, color: s.accentText),
              title: const Text('Запись телефонного звонка'),
              subtitle: Text('Включите запись звонков в «Телефоне», затем выберите файл. '
                  'Обычно папка: Music/Recordings/Call Recordings', style: TextStyle(color: s.muted)),
              onTap: () {
                Navigator.pop(context);
                importAudio(context, call: true);
              },
            ),
            ListTile(
              leading: Icon(Icons.audio_file_rounded, color: s.accentText),
              title: const Text('Аудиофайл'),
              subtitle: Text('Диктофон, голосовые, записи Телемоста и Zoom', style: TextStyle(color: s.muted)),
              onTap: () {
                Navigator.pop(context);
                importAudio(context);
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final filters = [('all', 'Все'), ('fav', 'Избранное'), for (final m in recModes) (m.id, m.label)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(children: [
          Text('Записи', style: display(24, color: s.text)),
          const Spacer(),
          IconButton(onPressed: _importMenu, icon: Icon(Icons.upload_file_rounded, color: s.text), tooltip: 'Импорт'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: TextField(
          controller: _q,
          focusNode: _focus,
          onChanged: _search,
          decoration: InputDecoration(
              hintText: 'Поиск по всем записям', prefixIcon: Icon(Icons.search_rounded, color: s.muted), isDense: true),
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          children: [
            for (final (k, label) in filters)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                    label: Text(label), selected: _filter == k, showCheckmark: false,
                    labelStyle: TextStyle(color: _filter == k ? s.onAccent : s.text, fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() => _filter = k)),
              ),
          ],
        ),
      ),
      Expanded(
        child: StreamBuilder<List<Recording>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Нет связи с сервером', style: TextStyle(color: s.muted)));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var list = _found ?? snap.data!;
            list = switch (_filter) {
              'all' => list,
              'fav' => list.where((r) => r.favorite).toList(),
              _ => list.where((r) => r.mode == _filter).toList(),
            };
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const MariOrb(size: 88),
                    const SizedBox(height: 20),
                    Text('Записей пока нет', style: display(18, color: s.text)),
                    const SizedBox(height: 8),
                    Text('Нажмите на шар внизу — Мари запишет,\nрасшифрует и выделит главное',
                        textAlign: TextAlign.center, style: TextStyle(color: s.muted, height: 1.4)),
                  ]),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
              itemCount: list.length,
              itemBuilder: (_, i) => RecordingTile(
                r: list[i],
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: list[i].id))),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
