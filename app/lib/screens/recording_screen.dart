import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../modes.dart';
import '../roles.dart';
import '../widgets/folder_sheet.dart';
import '../widgets/mari_orb.dart';
import '../services/api.dart';
import '../services/calendar.dart';
import '../services/local_files.dart';
import '../services/pdf_export.dart';
import '../services/uploader.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/player.dart';
import 'chat_screen.dart';
import 'home_screen.dart' show showModeSheet;
import 'paywall_screen.dart';
import 'prepare_screen.dart';

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
  Widget build(BuildContext context) => ValueListenableBuilder<Map<String, UploadState>>(
        valueListenable: Uploader.state,
        builder: (context, up, _) => _build(context, up[r.id]),
      );

  Widget _build(BuildContext context, UploadState? up) {
    final s = context.sm;
    final stage = r.stage;
    final uploaded = r.status != 'uploading';
    final transcribed = r.status == 'processing' && stage == 'summarizing';
    final diarizing = r.status == 'processing' && (stage == 'diarizing' || transcribed);
    Widget step(String title, String? sub, bool done, bool active, {double? value}) => Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: s.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(done ? Icons.check_circle_rounded : (active ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                  color: done ? s.success : (active ? s.accentText : s.muted), size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: s.text, fontWeight: FontWeight.w700))),
              if (sub != null) Text(sub, style: TextStyle(color: s.muted, fontSize: 13)),
            ]),
            if (active) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: value, minHeight: 6, color: s.accent, backgroundColor: s.border,
                  borderRadius: BorderRadius.circular(3)),
            ],
          ]),
        );
    final failed = r.status == 'error' || r.status == 'limit_exceeded';
    final dur = r.durationSec;
    final eta = dur == null ? null : 'примерно ${((dur * 0.3) / 60).ceil().clamp(1, 120)} мин';
    return Scaffold(
      appBar: AppBar(title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
        if (failed)
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.status == 'error' ? 'Не получилось обработать запись' : 'Закончились минуты в этом месяце',
                  style: display(17, color: s.text)),
              if (r.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.error!, style: TextStyle(color: s.muted))),
              const SizedBox(height: 14),
              if (r.status == 'limit_exceeded')
                FilledButton(
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
                    if (ok == true && context.mounted) await _retry(context);
                  },
                  child: const Text('Оформить подписку'),
                )
              else
                FilledButton(onPressed: () => _retry(context), child: const Text('Попробовать снова')),
            ]),
          )
        else ...[
          const SizedBox(height: 12),
          const Center(child: MariOrb(size: 140)),
          const SizedBox(height: 24),
          Center(child: Text(uploaded ? 'Мари разбирает запись' : 'Загружаю запись', style: display(20, color: s.text))),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
            child: Text(
                uploaded
                    ? 'Можно выйти из приложения — результат появится здесь.'
                    : 'Не закрывайте приложение до окончания загрузки. Если связь пропадёт — загрузка продолжится сама.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.muted, height: 1.4)),
          ),
          if (up?.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(children: [
                Text(up!.error!, textAlign: TextAlign.center, style: TextStyle(color: s.danger)),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => _retry(context), child: const Text('Повторить загрузку')),
              ]),
            ),
          step('Загрузка', uploaded ? null : (up == null ? null : '${(up.progress * 100).round()}%'), uploaded, !uploaded,
              value: up == null || up.progress == 0 ? null : up.progress),
          step('Расшифровка', r.status == 'processing' && !diarizing ? eta : null, diarizing,
              r.status == 'queued' || (r.status == 'processing' && !diarizing)),
          step('Спикеры', null, transcribed, r.status == 'processing' && stage == 'diarizing'),
          step('Итог и задачи', null, false, transcribed),
          if (r.status == 'queued')
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
              child: Text('В очереди на обработку', textAlign: TextAlign.center, style: TextStyle(color: s.muted)),
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
  String? _busy;

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
      _busy = null;
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

  void _changeMode() => showModeSheet(context, title: 'Тип записи', current: r.mode, onPick: (m) async {
        if (m == r.mode) return;
        setState(() {
          _loading = true;
          _busy = 'Мари пересобирает итог\nкак «${modeById(m).label}»…\nОбычно это меньше минуты';
        });
        try {
          await Api.resummarize(r.id, m);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не получилось: $e')));
        }
        await _load();
      });

  void _pdf() {
    final s = context.sm;
    if (_summary == null) return;
    Future<void> run(PdfTemplate t, bool print) async {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Готовлю PDF…'), duration: Duration(seconds: 2)));
      try {
        final bytes = await PdfExport.build(r, _summary!, _segs, t, folderName: folderById(r.folderId)?.name);
        if (print) {
          await Printing.layoutPdf(onLayout: (_) async => bytes, name: PdfExport.fileName(r, t));
        } else {
          await Printing.sharePdf(bytes: bytes, filename: PdfExport.fileName(r, t));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не получилось: $e')));
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: Text('PDF-конспект', style: display(18, color: s.text))),
            for (final t in PdfTemplate.values)
              ListTile(
                title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t.hint, style: TextStyle(color: s.muted)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Поделиться', onPressed: () => run(t, false), icon: Icon(Icons.ios_share_rounded, color: s.accentText)),
                  IconButton(tooltip: 'Печать', onPressed: () => run(t, true), icon: Icon(Icons.print_rounded, color: s.accentText)),
                ]),
              ),
          ]),
        ),
      ),
    );
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
                'move' => showMoveSheet(context, r),
                'mode' => _changeMode(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'share_sum', child: Text('Поделиться резюме')),
                PopupMenuItem(value: 'share_tr', child: Text('Поделиться транскриптом')),
                PopupMenuItem(value: 'move', child: Text('Положить на полку')),
                PopupMenuItem(value: 'mode', child: Text('Сменить тип записи')),
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          ],
        ),
        body: _loading
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const MariOrb(size: 72),
                  const SizedBox(height: 20),
                  Text(_busy ?? 'Открываю…', textAlign: TextAlign.center, style: TextStyle(color: context.sm.muted, fontSize: 15)),
                ]),
              )
            : NestedScrollView(
                headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(color: modeById(r.mode).color, borderRadius: BorderRadius.circular(99)),
                        child: Text(modeById(r.mode).label,
                            style: const TextStyle(color: Color(0xFF0F1015), fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      if (folderById(r.folderId) != null) ...[
                        const SizedBox(width: 6),
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: CircleAvatar(radius: 5, backgroundColor: hexColor(folderById(r.folderId)!.color)),
                          label: Text(folderById(r.folderId)!.name),
                          onPressed: () => showMoveSheet(context, r),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Text('${DateFormat('d MMM, HH:mm', 'ru').format(r.recordedAt)} · ${fmtDuration(r.durationSec)}',
                          style: TextStyle(color: context.sm.muted, fontSize: 13)),
                    ]),
                    const SizedBox(height: 10),
                    Text(r.title, style: display(21, color: context.sm.text)),
                  ]),
                )),
                SliverToBoxAdapter(child: SizedBox(
                  height: 60,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
                    _Action(Icons.chat_bubble_outline_rounded, 'Спросить Мари', () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ChatScreen(recording: r))), primary: true),
                    _Action(Icons.school_outlined, 'Подготовка', () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => PrepareScreen(recording: r)))),
                    _Action(Icons.picture_as_pdf_outlined, 'PDF-конспект', _pdf),
                    _Action(Icons.people_outline_rounded, 'Спикеры', _speakers),
                    _Action(Icons.ios_share_rounded, 'Поделиться', () => Share.share(_summaryText())),
                  ]),
                )),
                if (r.folderId == null && folderById(r.suggestedFolderId) != null)
                  SliverToBoxAdapter(child: _SuggestBanner(r: r, folder: folderById(r.suggestedFolderId)!)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    bar: TabBar(
                      labelColor: context.sm.text,
                      unselectedLabelColor: context.sm.muted,
                      indicatorColor: context.sm.accent,
                      indicatorWeight: 2.5,
                      dividerColor: context.sm.border,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      tabs: const [Tab(text: 'Итог'), Tab(text: 'Текст'), Tab(text: 'Задачи')],
                    ),
                  ),
                ),
                ],
                body: TabBarView(children: [
                  _SummaryTab(summary: _summary, title: r.title, onSeek: hasAudio ? _player.seek : null),
                  _TranscriptTab(r: r, segs: _segs, onTap: hasAudio ? _player.seek : null),
                  _TasksTab(recordingId: r.id),
                ]),
              ),
        bottomNavigationBar: hasAudio ? AudioPlayerBar(path: r.localAudio!, controller: _player) : null,
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabBar bar;
  final Color color;
  _TabsHeader({required this.bar, required this.color});
  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(color: color, child: bar);
  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.color != color;
}

class _SuggestBanner extends StatelessWidget {
  final Recording r;
  final Folder folder;
  const _SuggestBanner({required this.r, required this.folder});

  Future<void> _accept(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await Repo.moveToFolder(r.id, folder.id);
      m.showSnackBar(SnackBar(content: Text('Положила в «${folder.name}»')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('Не получилось: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: s.heroBorder)),
      child: Row(children: [
        const MariOrb(size: 26, glow: false),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _accept(context),
            child: Text('Похоже, это «${folder.name}». Положить туда?', style: TextStyle(color: s.text, fontSize: 14)),
          ),
        ),
        TextButton(
          onPressed: () => _accept(context),
          child: Text('Да', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w800)),
        ),
        IconButton(
          tooltip: 'Нет',
          onPressed: () => sb.from('recordings').update({'suggested_folder_id': null}).eq('id', r.id),
          icon: Icon(Icons.close_rounded, color: s.muted, size: 20),
        ),
      ]),
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
  final String title;
  final void Function(int ms)? onSeek;
  const _SummaryTab({required this.summary, required this.title, this.onSeek});

  Widget _time(BuildContext context, int? t) {
    if (t == null) return const SizedBox.shrink();
    final s = context.sm;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onSeek == null ? null : () => onSeek!(t * 1000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(fmtDuration(t), style: TextStyle(color: s.accentText, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _point(BuildContext context, KeyPoint k) {
    final s = context.sm;
    Widget body;
    switch (k.kind) {
      case 'definition':
        body = Text(k.text, style: TextStyle(color: s.chip, fontWeight: FontWeight.w700, height: 1.45, fontSize: 15));
      case 'formula':
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: s.card, border: Border.all(color: s.text.withValues(alpha: .35)), borderRadius: BorderRadius.circular(12)),
          child: SelectableText(k.text, style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 15)),
        );
      case 'example':
        body = Text(k.text, style: TextStyle(color: s.muted, fontStyle: FontStyle.italic, height: 1.45, fontSize: 15));
      case 'important':
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: s.danger.withValues(alpha: .12), border: Border.all(color: s.danger.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.star_rounded, color: s.danger, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(k.text, style: TextStyle(color: s.danger, fontWeight: FontWeight.w700, height: 1.4))),
          ]),
        );
      case 'mistake':
        body = Text('Частая ошибка: ${k.text}', style: TextStyle(color: s.success, fontWeight: FontWeight.w600, height: 1.45));
      default:
        body = Text(k.text, style: TextStyle(color: s.text, height: 1.45, fontSize: 15));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: body)),
        _time(context, k.tSec),
      ]),
    );
  }

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

  Widget _event(BuildContext context, EventItem e) {
    final s = context.sm;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.heroBorder),
        gradient: LinearGradient(colors: [s.heroStart, s.card], stops: const [0, .8]),
      ),
      child: Row(children: [
        Icon(Icons.event_rounded, color: s.accentText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 15)),
            Text(fmtEventDate(e), style: TextStyle(color: s.heroText, fontSize: 13)),
          ]),
        ),
        FilledButton(
          onPressed: () => CalendarService.add(e, recordingTitle: title),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
          child: const Text('В календарь'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final c = context.sm;
    if (s == null) return const Center(child: Text('Итога нет'));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
      SelectableText(s.summary, style: TextStyle(fontSize: 16, height: 1.55, color: c.text)),
      for (final e in s.events) _event(context, e),
      if (s.keyPoints.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Главное', style: display(14, color: c.muted, weight: FontWeight.w500)),
        const SizedBox(height: 10),
        for (final k in s.keyPoints) _point(context, k),
      ],
      if (s.explanations.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.help_outline_rounded, color: c.accentText, size: 20),
              const SizedBox(width: 8),
              Text('Мари объясняет', style: display(14, color: c.text, weight: FontWeight.w500)),
            ]),
            for (final x in s.explanations) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('${x['topic'] ?? ''}', style: TextStyle(color: c.text, fontWeight: FontWeight.w700))),
                _time(context, (x['t_sec'] as num?)?.toInt()),
              ]),
              const SizedBox(height: 4),
              Text('${x['answer'] ?? ''}', style: TextStyle(color: c.text, height: 1.45)),
            ],
          ]),
        ),
      ],
      for (final (t, items) in s.sections) _section(context, t, items),
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
    final s = context.sm;
    return StreamBuilder<List<TaskItem>>(
      stream: Repo.tasks(),
      builder: (context, snap) {
        final tasks = (snap.data ?? []).where((t) => t.recordingId == recordingId).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('В этой записи задач не нашлось', textAlign: TextAlign.center, style: TextStyle(color: s.muted)),
            ),
          for (final t in tasks)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: s.border)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconButton(
                  tooltip: t.done ? 'Вернуть' : 'Выполнено',
                  onPressed: () => Repo.setTaskDone(t.id, !t.done),
                  icon: Icon(t.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: t.done ? s.success : s.teal, size: 26),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 8, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.text,
                          style: TextStyle(
                              color: t.done ? s.muted : s.text,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              decoration: t.done ? TextDecoration.lineThrough : null)),
                      if (t.forMe || t.assignee != null || t.dueText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              [if (t.forMe) 'Вам', if (!t.forMe && t.assignee != null) t.assignee!, if (t.dueText != null) 'срок: ${t.dueText}']
                                  .join(' · '),
                              style: TextStyle(color: t.forMe ? s.accentText : s.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить',
                  onPressed: () => Repo.deleteTask(t.id),
                  icon: Icon(Icons.close_rounded, color: s.muted, size: 20),
                ),
              ]),
            ),
          TextButton.icon(
            onPressed: () async {
              final c = TextEditingController();
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Новая задача'),
                  content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Что сделать')),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Добавить'))],
                ),
              );
              if (v != null && v.trim().isNotEmpty) await Repo.addTask(v.trim(), recordingId: recordingId);
            },
            icon: Icon(Icons.add_rounded, color: s.accentText),
            label: Text('Добавить задачу', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w700)),
          ),
        ]);
      },
    );
  }
}
