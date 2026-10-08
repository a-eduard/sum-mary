import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../modes.dart';
import '../services/calendar.dart';
import '../services/local_files.dart';
import '../services/notifications.dart';
import '../services/repo.dart';
import '../services/uploader.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';
import '../roles.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/recording_tile.dart';
import '../widgets/start_sheet.dart';
import 'chat_screen.dart';
import 'prepare_screen.dart';
import 'record_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  final _statuses = <String, String>{};
  StreamSubscription<List<Recording>>? _recSub;
  StreamSubscription<List<TaskItem>>? _taskSub;
  List<TaskItem> _tasks = [];
  List<EventItem> _events = [];

  @override
  void initState() {
    super.initState();
    Repo.pendingUploads().then(Uploader.resumePending).catchError((_) {});
    Notifications.askPermission();
    Notifications.openRecording.addListener(_openFromNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromNotification());
    _recSub = Repo.recordings().listen((list) {
      for (final r in list) {
        final prev = _statuses[r.id];
        if (prev != null && prev != 'ready' && r.status == 'ready') _onReady(r);
        _statuses[r.id] = r.status;
      }
    });
    _taskSub = Repo.tasks().listen((t) {
      _tasks = t;
      _reschedule();
    });
    // Ответы поддержки: всплывашка в приложении или уведомление, если оно свёрнуто.
    _supportSub = Repo.support().listen((list) {
      final unread = list.where((m) => !m.fromMe && m.readAt == null).toList();
      final fresh = unread.where((m) => !_supportSeen.contains(m.id)).toList();
      final first = _supportSeen.isEmpty && !_supportLoaded;
      _supportLoaded = true;
      _supportSeen.addAll(list.map((m) => m.id));
      if (fresh.isEmpty || first) return;
      final text = fresh.last.text;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ответ поддержки: $text', maxLines: 2, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(label: 'Открыть', onPressed: _openSupport),
        ));
      } else {
        Notifications.supportReply(text);
      }
    });
    _loadEvents();
  }

  StreamSubscription<List<SupportMsg>>? _supportSub;
  final _supportSeen = <String>{};
  bool _supportLoaded = false;

  void _openSupport() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()));

  Future<void> _loadEvents() async {
    try {
      _events = await Repo.upcomingEvents();
      _reschedule();
    } catch (_) {}
  }

  void _reschedule() => Notifications.reschedule(_events, _tasks).catchError((_) {});

  void _onReady(Recording r) {
    _loadEvents();
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Итог готов: ${r.title}'),
        action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: r.id)))),
      ));
    } else {
      Notifications.recordingReady(r);
    }
  }

  void _openFromNotification() {
    final id = Notifications.openRecording.value;
    if (id == null || !mounted) return;
    Notifications.openRecording.value = null;
    if (id == 'support') return _openSupport();
    Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: id)));
  }

  @override
  void dispose() {
    _supportSub?.cancel();
    _recSub?.cancel();
    _taskSub?.cancel();
    Notifications.openRecording.removeListener(_openFromNotification);
    super.dispose();
  }
  final _recordingsKey = GlobalKey<RecordingsPageState>();

  void _record([String mode = 'meeting', String? folderId]) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecordScreen(mode: mode, folderId: folderId)));

  void _askAndRecord(String mode) => showStartSheet(context, mode: mode, onStart: _record);

  void _openSearch() => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(
        onRecord: _askAndRecord,
        onAsk: _openSearch,
        onImportCall: () => showStartSheet(context,
            mode: 'call', importCall: true, onStart: (m, f) => importAudio(context, call: true, mode: m, folderId: f)),
      ),
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
        onRecordLong: () => _askAndRecord('meeting'),
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
    Widget item(int i, IconData icon, String label) {
      final sel = index == i;
      final c = sel ? s.text : s.muted;
      return Expanded(
        child: Semantics(
          selected: sel,
          button: true,
          child: InkResponse(
            onTap: () => onTap(i),
            radius: 36,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 24, color: sel ? s.accentText : c),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.clip,
                  style: TextStyle(color: c, fontSize: 11, fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
            ]),
          ),
        ),
      );
    }
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
                    SizedBox(
                      width: 80,
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('Запись', style: TextStyle(color: s.muted, fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                      ]),
                    ),
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
                  child: const MariOrb(size: 62, child: Icon(Icons.mic_rounded, size: 28, color: Color(0xFF0F1015))),
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
void showModeSheet(BuildContext context,
    {required void Function(String) onPick, String title = 'Что записываем?', String? current}) {
  final s = context.sm;
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: display(18, color: s.text)),
          if (current != null) ...[
            const SizedBox(height: 6),
            Text('Мари перепишет итог под выбранный тип', style: TextStyle(color: s.muted, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in recModes)
              ActionChip(
                avatar: Icon(m.id == current ? Icons.check_rounded : m.icon, size: 18, color: m.color),
                side: m.id == current ? BorderSide(color: m.color, width: 1.5) : null,
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
Future<void> importAudio(BuildContext context, {bool call = false, String? mode, String? folderId}) async {
  // Аудио и видео (записи Телемоста/Zoom в .mp4) — сервер сам вытащит звук.
  final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowMultiple: true, allowedExtensions: const [
    'm4a', 'mp3', 'wav', 'ogg', 'oga', 'opus', 'aac', 'flac', 'amr', '3gp', 'wma', 'mp4', 'mov', 'webm', 'mkv',
  ]);
  if (res == null) return;
  for (final f in res.files.where((f) => f.path != null)) {
    final copy = await LocalFiles.importCopy(f.path!);
    final id = await Repo.createRecording(
        source: call ? 'call' : 'import', mode: mode ?? (call ? 'call' : 'auto'), folderId: folderId, localPath: copy.path);
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
  late Future<List<EventItem>> _events = Repo.upcomingEvents();
  String? _name;
  bool _askName = false;
  final _nameCtrl = TextEditingController();

  void _onMe() {
    final p = Repo.me.value;
    if (p == null || !mounted) return;
    final n = p.displayName?.trim() ?? '';
    setState(() {
      _name = n.isEmpty ? null : n;
      _askName = n.isEmpty;
    });
  }

  @override
  void initState() {
    super.initState();
    Repo.me.addListener(_onMe);
    _onMe();
    Repo.profile().then((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    Repo.me.removeListener(_onMe);
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final n = _nameCtrl.text.trim();
    if (n.isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      await Repo.saveName(n, Repo.me.value?.nameAliases ?? const []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    }
  }

  Widget _nameCard(Sm s) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: s.heroBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Как вас зовут?', style: display(16, color: s.text)),
          const SizedBox(height: 4),
          Text('Мари будет обращаться по имени и узнавать в записях задачи, которые дают именно вам.',
              style: TextStyle(color: s.muted, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveName(),
                decoration: const InputDecoration(hintText: 'Имя', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _saveName, child: const Text('Готово')),
          ]),
        ]),
      );

  Future<void> _refresh() async {
    final f = Repo.upcomingEvents();
    setState(() => _events = f);
    await f.catchError((_) => <EventItem>[]);
  }

  Future<void> _open(String recordingId) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: recordingId)));
    if (mounted) _refresh();
  }

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
      RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 140), children: [
        Row(children: [
          const MariOrb(size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(date, style: TextStyle(color: s.muted, fontSize: 14)),
              const SizedBox(height: 4),
              Text(_name == null ? _greeting() : '${_greeting()},\n$_name', style: display(22, color: s.text)),
            ]),
          ),
        ]),
        // Слот всегда на месте: если вставлять/убирать виджет, индексы детей ListView
        // сдвигаются и StreamBuilder'ы ниже переподписываются на одноразовый поток.
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: _askName ? _nameCard(s) : const SizedBox(width: double.infinity),
        ),
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
        FutureBuilder<List<EventItem>>(
          future: _events,
          builder: (context, ev) => StreamBuilder<List<TaskItem>>(
            stream: _tasks,
            builder: (context, snap) {
              final events = (ev.data ?? []).take(2).toList();
              final open = (snap.data ?? []).where((t) => !t.done).toList()
                ..sort((a, b) {
                  if (a.forMe != b.forMe) return a.forMe ? -1 : 1; // сначала мои
                  return (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100));
                });
              final tasks = open.take(3).toList();
              if (events.isEmpty && tasks.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                section('Ближайшее'),
                for (final e in events)
                  _HeroEvent(
                    event: e,
                    onOpen: () => _open(e.recordingId),
                    onDismiss: () async {
                      await Repo.dismissEvent(e);
                      _refresh();
                    },
                  ),
                for (final t in tasks) _TaskRow(task: t, onOpen: _open),
              ]);
            },
          ),
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
                    onTap: () => _open(r.id),
                  ),
            ]);
          },
        ),
      ]),
      ),
    ]);
  }
}

/// Открывает тест по записи (запись подгружается по id).
class _PrepareFor extends StatelessWidget {
  final String recordingId;
  const _PrepareFor({required this.recordingId});
  @override
  Widget build(BuildContext context) => StreamBuilder<Recording?>(
        stream: Repo.recording(recordingId),
        builder: (_, snap) => snap.data == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : PrepareScreen(recording: snap.data, start: 'quiz'),
      );
}

class _HeroEvent extends StatelessWidget {
  final EventItem event;
  final VoidCallback onOpen, onDismiss;
  const _HeroEvent({required this.event, required this.onOpen, required this.onDismiss});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final label = switch (event.kind) {
      'test' => 'Контрольная',
      'meeting' => 'Встреча',
      'deadline' => 'Дедлайн',
      'homework' => 'Домашнее задание',
      _ => 'Событие',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.heroBorder),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.heroStart, s.card], stops: const [0, .75]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('$label · ${fmtEventDate(event)}',
                style: TextStyle(color: s.heroText, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Убрать',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, color: s.muted, size: 20),
          ),
        ]),
        const SizedBox(height: 6),
        Text(event.title, style: TextStyle(color: s.text, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (event.kind == 'test' || event.kind == 'homework')
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _PrepareFor(recordingId: event.recordingId))),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Повторить'),
            ),
          FilledButton(
            onPressed: () => CalendarService.add(event),
            style: FilledButton.styleFrom(backgroundColor: s.invBg, foregroundColor: s.invText, minimumSize: const Size(0, 44)),
            child: const Text('В календарь'),
          ),
          TextButton(
            onPressed: onOpen,
            child: Text('Открыть запись', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskItem task;
  final void Function(String recordingId) onOpen;
  const _TaskRow({required this.task, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Dismissible(
      key: ValueKey('today-${task.id}'),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(color: s.success.withValues(alpha: .18), borderRadius: BorderRadius.circular(22)),
        child: Icon(Icons.check_rounded, color: s.success),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: s.danger.withValues(alpha: .15), borderRadius: BorderRadius.circular(22)),
        child: Icon(Icons.delete_outline_rounded, color: s.danger),
      ),
      onDismissed: (d) => d == DismissDirection.startToEnd ? Repo.setTaskDone(task.id, true) : Repo.deleteTask(task.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: task.recordingId == null ? null : () => onOpen(task.recordingId!),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
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
                  if (task.dueText != null || task.assignee != null || task.forMe)
                    Text([
                      if (task.forMe) 'Вам' else if (task.assignee != null) task.assignee!,
                      if (task.dueText != null) task.dueText!,
                    ].join(' · '),
                        style: TextStyle(color: s.muted, fontSize: 13)),
                ]),
              ),
              if (task.recordingId != null) Icon(Icons.chevron_right_rounded, color: s.muted),
            ]),
          ),
        ),
      ),
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
                importAudio(context, call: true, folderId: folderById(_filter)?.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.audio_file_rounded, color: s.accentText),
              title: const Text('Аудиофайл'),
              subtitle: Text('Диктофон, голосовые, записи Телемоста и Zoom', style: TextStyle(color: s.muted)),
              onTap: () {
                Navigator.pop(context);
                importAudio(context, folderId: folderById(_filter)?.id);
              },
            ),
          ]),
        ),
      ),
    );
  }

  final _scaffold = GlobalKey<ScaffoldState>();
  List<Recording> _all = [];

  String _filterName() => switch (_filter) {
        'all' => 'Все записи',
        'inbox' => 'Входящие',
        'fav' => 'Избранное',
        _ => folderById(_filter)?.name ?? 'Все записи',
      };

  Widget _drawer(Sm s) => Drawer(
        backgroundColor: s.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
        child: SafeArea(
          child: ValueListenableBuilder<List<Folder>>(
            valueListenable: Repo.folders,
            builder: (context, folders, _) {
              int count(bool Function(Recording) f) => _all.where(f).length;
              Widget row(String k, String label, int n, {Widget? lead}) {
                final sel = _filter == k;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Material(
                    color: sel ? s.accent.withValues(alpha: context.isDark ? .22 : .12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: lead,
                      title: Text(label, style: TextStyle(color: s.text, fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                      trailing: Text('$n', style: TextStyle(color: s.muted, fontWeight: FontWeight.w600)),
                      onTap: () {
                        setState(() => _filter = k);
                        Navigator.pop(context);
                      },
                      onLongPress: folders.any((f) => f.id == k) ? () => _folderMenu(folders.firstWhere((f) => f.id == k)) : null,
                    ),
                  ),
                );
              }

              return ListView(padding: const EdgeInsets.only(top: 20, bottom: 120), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Text('Полки', style: display(22, color: s.text)),
                ),
                row('all', 'Все записи', _all.length, lead: Icon(Icons.all_inbox_rounded, color: s.muted)),
                row('inbox', 'Входящие', count((r) => r.folderId == null), lead: Icon(Icons.inbox_rounded, color: s.muted)),
                row('fav', 'Избранное', count((r) => r.favorite), lead: const Icon(Icons.favorite_rounded, color: AppColors.record)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8), child: Divider(color: s.border)),
                for (final f in folders)
                  row(f.id, f.name, count((r) => r.folderId == f.id),
                      lead: Container(width: 14, height: 14, decoration: BoxDecoration(color: hexColor(f.color), shape: BoxShape.circle))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(Icons.add_rounded, color: s.accentText),
                    title: Text('Новая полка', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w700)),
                    onTap: () async {
                      final name = await askFolderName(context);
                      if (name != null) await Repo.addFolder(name, folderColors[folders.length % folderColors.length]);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
                  child: Text('Удержите полку, чтобы удалить её', style: TextStyle(color: s.muted, fontSize: 12)),
                ),
              ]);
            },
          ),
        ),
      );

  Future<void> _folderMenu(Folder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить полку «${f.name}»?'),
        content: const Text('Записи с этой полки не удалятся — они переедут во «Входящие».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await Repo.deleteFolder(f.id);
      if (_filter == f.id) setState(() => _filter = 'all');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final folder = folderById(_filter);
    return Scaffold(
      key: _scaffold,
      backgroundColor: Colors.transparent,
      drawer: _drawer(s),
      drawerEdgeDragWidth: 32,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
        child: Row(children: [
          IconButton(
            tooltip: 'Полки',
            onPressed: () => _scaffold.currentState?.openDrawer(),
            icon: Icon(Icons.menu_rounded, color: s.text),
          ),
          if (folder != null) ...[
            Container(width: 12, height: 12, decoration: BoxDecoration(color: hexColor(folder.color), shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GestureDetector(
              onTap: () => _scaffold.currentState?.openDrawer(),
              child: Text(_filterName(), maxLines: 1, overflow: TextOverflow.ellipsis, style: display(22, color: s.text)),
            ),
          ),
          if (folder != null)
            IconButton(
              tooltip: 'Подготовка по полке',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PrepareScreen(folder: folder))),
              icon: Icon(Icons.school_outlined, color: s.text),
            ),
          IconButton(
            tooltip: folder == null ? 'Спросить Мари по всем записям' : 'Спросить Мари по полке',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(folder: folder))),
            icon: Icon(Icons.chat_bubble_outline_rounded, color: s.text),
          ),
          IconButton(onPressed: _importMenu, icon: Icon(Icons.upload_file_rounded, color: s.text), tooltip: 'Импорт'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: TextField(
          controller: _q,
          focusNode: _focus,
          onChanged: _search,
          decoration: InputDecoration(
              hintText: 'Поиск по всем записям', prefixIcon: Icon(Icons.search_rounded, color: s.muted), isDense: true),
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
            _all = snap.data!;
            var list = _found ?? snap.data!;
            list = switch (_filter) {
              'all' => list,
              'fav' => list.where((r) => r.favorite).toList(),
              'inbox' => list.where((r) => r.folderId == null).toList(),
              _ => list.where((r) => r.folderId == _filter).toList(),
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
                onLongPress: () => showMoveSheet(context, list[i]),
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: list[i].id))),
              ),
            );
          },
        ),
      ),
    ]),
    );
  }
}
