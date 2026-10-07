import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../modes.dart';
import '../widgets/mari_orb.dart';
import '../services/local_files.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/player.dart';
import 'chat_screen.dart';
import 'paywall_screen.dart';

/// Карточка записи: статус обработки или результат (Резюме / Транскрипт / Задачи).
class RecordingScreen extends StatefulWidget {
  final String recordingId;
  const RecordingScreen({super.key, required this.recordingId});
  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final Stream<Recording?> _stream = Repo.recording(widget.recordingId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Recording?>(
      stream: _stream,
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        if (r.isReady) return _ReadyView(key: ValueKey(r.processedAt), r: r);
        return _ProcessingView(r: r);
      },
    );
  }
}

// ---------------- обработка ----------------
class _ProcessingView extends StatelessWidget {
  final Recording r;
  const _ProcessingView({required this.r});

  Future<void> _retry(BuildContext context) async {
    if (!LocalFiles.exists(r.localAudio)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Файл записи не найден на устройстве')));
      return;
    }
    await Repo.uploadAndQueue(r.id, File(r.localAudio!));
  }

  @override
  Widget build(BuildContext context) {
    final stage = r.stage;
    final uploaded = r.status != 'uploading';
    final transcribed = r.status == 'processing' && stage == 'summarizing';
    Widget step(String title, bool done, bool active) => Card(
          child: ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                value: done ? 1 : (active ? null : 0),
                minHeight: 6,
                color: context.sm.accent,
                backgroundColor: context.sm.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
        if (r.status == 'error' || r.status == 'limit_exceeded')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.status == 'error' ? 'Не получилось обработать запись' : 'Закончились бесплатные минуты',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (r.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.error!)),
                const SizedBox(height: 12),
                if (r.status == 'limit_exceeded')
                  FilledButton(
                    onPressed: () async {
                      final ok = await Navigator.push<bool>(
                          context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
                      if (ok == true && context.mounted) await _retry(context);
                    },
                    child: const Text('Оформить подписку'),
                  )
                else
                  FilledButton(onPressed: () => _retry(context), child: const Text('Попробовать снова')),
              ]),
            ),
          )
        else ...[
          const SizedBox(height: 12),
          const Center(child: MariOrb(size: 140)),
          const SizedBox(height: 24),
          Center(child: Text('Мари разбирает запись', style: display(20, color: context.sm.text))),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
            child: Text('Можно выйти из приложения — результат появится здесь, а мы пришлём уведомление.',
                textAlign: TextAlign.center, style: TextStyle(color: context.sm.muted, height: 1.4)),
          ),
          step('Загрузка аудио', uploaded, !uploaded),
          step('Расшифровка и спикеры', transcribed, r.status == 'processing' && !transcribed),
          step('Резюме и задачи', false, transcribed),
          if (r.status == 'uploading' && LocalFiles.exists(r.localAudio))
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(onPressed: () => _retry(context), child: const Text('Отправить ещё раз')),
            ),
        ],
      ]),
    );
  }
}

// ---------------- результат ----------------
class _ReadyView extends StatefulWidget {
  final Recording r;
  const _ReadyView({super.key, required this.r});
  @override
  State<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends State<_ReadyView> {
  Recording get r => widget.r;
  final _player = PlayerController();
  List<Segment> _segs = [];
  Summary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Future.wait([Repo.segments(r.id), Repo.summary(r.id)]);
    if (!mounted) return;
    setState(() {
      _segs = res[0] as List<Segment>;
      _summary = res[1] as Summary?;
      _loading = false;
    });
  }

  String _transcriptText() =>
      groupTurns(_segs).map((t) => '[${fmtMs(t.startMs)}] ${r.speakerName(t.speaker)}: ${t.text}').join('\n\n');

  String _summaryText() {
    final s = _summary;
    if (s == null) return '';
    final b = StringBuffer('${r.title}\n\n${s.summary}\n');
    if (s.decisions.isNotEmpty) b.write('\nРешения:\n${s.decisions.map((e) => '• $e').join('\n')}\n');
    if (s.openQuestions.isNotEmpty) b.write('\nОткрытые вопросы:\n${s.openQuestions.map((e) => '• $e').join('\n')}\n');
    b.write('\n— СамМари, sum-mary.ru');
    return b.toString();
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: r.title);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Название'),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Сохранить'))],
      ),
    );
    if (v != null && v.trim().isNotEmpty) await Repo.rename(r.id, v.trim());
  }

  Future<void> _speakers() async {
    final ids = _segs.map((s) => s.speaker).toSet().toList()..sort();
    final ctrls = {for (final n in ids) n: TextEditingController(text: r.speakerNames['$n'] ?? '')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Спикеры'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final n in ids)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(controller: ctrls[n], decoration: InputDecoration(labelText: 'Спикер $n', hintText: 'Имя')),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить'))],
      ),
    );
    if (ok == true) {
      await Repo.setSpeakerNames(r.id, {for (final e in ctrls.entries) '${e.key}': e.value.text.trim()});
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить запись?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await Repo.delete(r.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = LocalFiles.exists(r.localAudio);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: Icon(r.favorite ? Icons.favorite : Icons.favorite_border, color: AppColors.record),
              onPressed: () => Repo.setFavorite(r.id, !r.favorite),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'share_sum' => Share.share(_summaryText()),
                'share_tr' => Share.share(_transcriptText()),
                'rename' => _rename(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'share_sum', child: Text('Поделиться резюме')),
                PopupMenuItem(value: 'share_tr', child: Text('Поделиться транскриптом')),
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(color: modeById(r.mode).color, borderRadius: BorderRadius.circular(99)),
                        child: Text(modeById(r.mode).label,
                            style: const TextStyle(color: Color(0xFF0F1015), fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      Text('${DateFormat('d MMM, HH:mm', 'ru').format(r.recordedAt)} · ${fmtDuration(r.durationSec)}',
                          style: TextStyle(color: context.sm.muted, fontSize: 13)),
                    ]),
                    const SizedBox(height: 10),
                    Text(r.title, style: display(21, color: context.sm.text)),
                  ]),
                ),
                SizedBox(
                  height: 60,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
                    _Action(Icons.chat_bubble_outline_rounded, 'Спросить Мари', () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ChatScreen(recording: r))), primary: true),
                    _Action(Icons.people_outline_rounded, 'Спикеры', _speakers),
                    _Action(Icons.ios_share_rounded, 'Поделиться', () => Share.share(_summaryText())),
                  ]),
                ),
                TabBar(
                  labelColor: context.sm.text,
                  unselectedLabelColor: context.sm.muted,
                  indicatorColor: context.sm.accent,
                  indicatorWeight: 2.5,
                  dividerColor: context.sm.border,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  tabs: const [Tab(text: 'Итог'), Tab(text: 'Текст'), Tab(text: 'Задачи')],
                ),
                Expanded(
                  child: TabBarView(children: [
                    _SummaryTab(summary: _summary),
                    _TranscriptTab(r: r, segs: _segs, onTap: hasAudio ? _player.seek : null),
                    _TasksTab(recordingId: r.id),
                  ]),
                ),
              ]),
        bottomNavigationBar: hasAudio ? AudioPlayerBar(path: r.localAudio!, controller: _player) : null,
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _Action(this.icon, this.label, this.onTap, {this.primary = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: primary
            ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)))
            : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16))),
      );
}

class _SummaryTab extends StatelessWidget {
  final Summary? summary;
  const _SummaryTab({required this.summary});

  Widget _section(BuildContext context, String title, List<String> items) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: display(14, color: context.sm.muted, weight: FontWeight.w500)),
          const SizedBox(height: 8),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: TextStyle(color: context.sm.accent)),
                Expanded(child: Text(i, style: const TextStyle(height: 1.4))),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const Center(child: Text('Резюме нет'));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
      SelectableText(s.summary, style: TextStyle(fontSize: 16, height: 1.55, color: context.sm.text)),
      if (s.decisions.isNotEmpty) _section(context, 'Решения', s.decisions),
      if (s.responsibilities.isNotEmpty)
        _section(context, 'Кто за что отвечает', s.responsibilities.map((e) => '${e['person']} — ${e['area']}').toList()),
      if (s.openQuestions.isNotEmpty) _section(context, 'Открытые вопросы', s.openQuestions),
    ]);
  }
}

class _TranscriptTab extends StatelessWidget {
  final Recording r;
  final List<Segment> segs;
  final void Function(int ms)? onTap;
  const _TranscriptTab({required this.r, required this.segs, this.onTap});

  static const _colors = [Color(0xFF7C6CF2), Color(0xFF2EC4B6), Color(0xFFFF9F1C), Color(0xFFFF4D6D),
    Color(0xFF4CC9F0), Color(0xFFB5E48C), Color(0xFFF15BB5), Color(0xFFC0C0C0)];

  @override
  Widget build(BuildContext context) {
    final turns = groupTurns(segs);
    if (turns.isEmpty) return const Center(child: Text('Речь не найдена'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: turns.length,
      itemBuilder: (_, i) {
        final t = turns[i];
        final c = _colors[(t.speaker - 1) % _colors.length];
        return InkWell(
          onTap: onTap == null ? null : () => onTap!(t.startMs),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 5, backgroundColor: c),
                const SizedBox(width: 8),
                Text(r.speakerName(t.speaker), style: TextStyle(color: c, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(fmtMs(t.startMs), style: TextStyle(color: context.sm.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              Text(t.text, style: const TextStyle(height: 1.45)),
            ]),
          ),
        );
      },
    );
  }
}

class _TasksTab extends StatelessWidget {
  final String recordingId;
  const _TasksTab({required this.recordingId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TaskItem>>(
      stream: Repo.tasks(),
      builder: (context, snap) {
        final tasks = (snap.data ?? []).where((t) => t.recordingId == recordingId).toList();
        return ListView(padding: const EdgeInsets.all(8), children: [
          if (tasks.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Задач не найдено', textAlign: TextAlign.center)),
          for (final t in tasks)
            CheckboxListTile(
              value: t.done,
              onChanged: (v) => Repo.setTaskDone(t.id, v ?? false),
              title: Text(t.text, style: TextStyle(decoration: t.done ? TextDecoration.lineThrough : null)),
              subtitle: Text([if (t.assignee != null) t.assignee!, if (t.dueText != null) 'срок: ${t.dueText}'].join(' · ')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          TextButton.icon(
            onPressed: () async {
              final c = TextEditingController();
              final v = await showDialog<String>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Новая задача'),
                  content: TextField(controller: c, autofocus: true),
                  actions: [TextButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Добавить'))],
                ),
              );
              if (v != null && v.trim().isNotEmpty) await Repo.addTask(v.trim(), recordingId: recordingId);
            },
            icon: const Icon(Icons.add),
            label: const Text('Добавить задачу'),
          ),
        ]);
      },
    );
  }
}
