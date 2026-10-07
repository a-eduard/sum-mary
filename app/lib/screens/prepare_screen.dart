import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';

/// Подготовка к контрольной/экзамену: тест, карточки, ответы на билеты.
class PrepareScreen extends StatefulWidget {
  final Recording? recording;
  final Folder? folder;
  final String? start; // сразу открыть: quiz | cards | tickets
  const PrepareScreen({super.key, this.recording, this.folder, this.start});
  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends State<PrepareScreen> {
  String? _kind;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final _tickets = TextEditingController();

  String get _scope => widget.recording?.title ?? (widget.folder != null ? 'Полка «${widget.folder!.name}»' : 'Все записи');

  @override
  void initState() {
    super.initState();
    if (widget.start != null && widget.start != 'tickets') _run(widget.start!);
    if (widget.start == 'tickets') _kind = 'tickets';
  }

  Future<void> _run(String kind) async {
    setState(() {
      _kind = kind;
      _loading = true;
      _error = null;
      _items = [];
    });
    try {
      final items = await Api.prepare(kind,
          recordingId: widget.recording?.id, folderId: widget.folder?.id, tickets: _tickets.text, count: kind == 'cards' ? 15 : 10);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final title = switch (_kind) { 'quiz' => 'Тест', 'cards' => 'Карточки', 'tickets' => 'Билеты', _ => 'Подготовка' };
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: display(17, color: s.text)),
          Text(_scope, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.muted, fontSize: 12)),
        ]),
        leading: _kind != null && widget.start == null
            ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _kind = null))
            : null,
      ),
      body: _loading
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const MariOrb(size: 110),
                const SizedBox(height: 24),
                Text(switch (_kind) { 'quiz' => 'Мари составляет тест…', 'cards' => 'Мари готовит карточки…', _ => 'Мари отвечает на билеты…' },
                    style: display(17, color: s.text)),
                const SizedBox(height: 8),
                Text('Обычно это занимает до минуты', style: TextStyle(color: s.muted)),
              ]),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: s.danger)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => _run(_kind!), child: const Text('Попробовать снова')),
                    ]),
                  ),
                )
              : switch (_kind) {
                  null => _menu(s),
                  'quiz' => _Quiz(items: _items, onAgain: () => _run('quiz')),
                  'cards' => _Cards(items: _items),
                  _ => _items.isEmpty ? _ticketsInput(s) : _TicketAnswers(items: _items),
                },
    );
  }

  Widget _menu(Sm s) {
    Widget card(String kind, IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: s.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: s.border)),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => kind == 'tickets' ? setState(() => _kind = 'tickets') : _run(kind),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: s.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: s.accentText),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(color: s.text, fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(color: s.muted, fontSize: 13, height: 1.3)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: s.muted),
                ]),
              ),
            ),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      Text('Как будем готовиться?', style: display(20, color: s.text)),
      const SizedBox(height: 16),
      card('quiz', Icons.quiz_rounded, 'Тест', '10 вопросов с вариантами ответа и объяснениями'),
      card('cards', Icons.style_rounded, 'Карточки', 'Термины и формулы — переворачивайте и запоминайте'),
      card('tickets', Icons.assignment_rounded, 'Ответы на билеты', 'Вставьте список билетов — Мари ответит словами преподавателя'),
    ]);
  }

  Widget _ticketsInput(Sm s) => ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
        Text('Список билетов', style: display(20, color: s.text)),
        const SizedBox(height: 8),
        Text('Вставьте вопросы к экзамену — каждый с новой строки. Мари найдёт ответы в записях лекций и подскажет, чего в них нет.',
            style: TextStyle(color: s.muted, height: 1.4)),
        const SizedBox(height: 14),
        TextField(
          controller: _tickets,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(hintText: '1. Предел функции. Определение по Коши\n2. Теорема Ролля\n3. …'),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 56, child: FilledButton(onPressed: () => _run('tickets'), child: const Text('Получить ответы'))),
      ]);
}

// ---------- тест ----------
class _Quiz extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onAgain;
  const _Quiz({required this.items, required this.onAgain});
  @override
  State<_Quiz> createState() => _QuizState();
}

class _QuizState extends State<_Quiz> {
  int _i = 0, _score = 0;
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final items = widget.items;
    if (_i >= items.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MariOrb(size: 96),
            const SizedBox(height: 20),
            Text('$_score из ${items.length}', style: display(32, color: s.text)),
            const SizedBox(height: 6),
            Text(_score >= items.length * .8 ? 'Отлично! Вы готовы.' : (_score >= items.length * .5 ? 'Неплохо, повторите ошибки.' : 'Стоит повторить конспект.'),
                style: TextStyle(color: s.muted)),
            const SizedBox(height: 20),
            FilledButton(onPressed: widget.onAgain, child: const Text('Новый тест')),
          ]),
        ),
      );
    }
    final q = items[_i];
    final options = List<String>.from((q['options'] as List? ?? []).map((e) => '$e'));
    final answer = (q['answer'] as num?)?.toInt() ?? 0;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: (_i + 1) / items.length, minHeight: 6, color: s.accent, backgroundColor: s.border),
      ),
      const SizedBox(height: 8),
      Text('Вопрос ${_i + 1} из ${items.length}', style: TextStyle(color: s.muted, fontSize: 13)),
      const SizedBox(height: 14),
      Text('${q['q'] ?? ''}', style: TextStyle(color: s.text, fontSize: 19, fontWeight: FontWeight.w700, height: 1.35)),
      const SizedBox(height: 18),
      for (var k = 0; k < options.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: _picked == null
                ? s.card
                : (k == answer ? s.success.withValues(alpha: .16) : (k == _picked ? s.danger.withValues(alpha: .14) : s.card)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                  color: _picked == null ? s.border : (k == answer ? s.success : (k == _picked ? s.danger : s.border)), width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _picked != null
                  ? null
                  : () => setState(() {
                        _picked = k;
                        if (k == answer) _score++;
                      }),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Text(String.fromCharCode(65 + k), style: TextStyle(color: s.accentText, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(options[k], style: TextStyle(color: s.text, fontSize: 15, height: 1.3))),
                  if (_picked != null && k == answer) Icon(Icons.check_rounded, color: s.success),
                ]),
              ),
            ),
          ),
        ),
      if (_picked != null) ...[
        const SizedBox(height: 6),
        Text('${q['explain'] ?? ''}', style: TextStyle(color: s.text, height: 1.45)),
        if (q['source'] != null && '${q['source']}' != 'null')
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Источник: ${q['source']}', style: TextStyle(color: s.muted, fontSize: 13))),
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: () => setState(() {
              _i++;
              _picked = null;
            }),
            child: Text(_i + 1 < items.length ? 'Дальше' : 'Результат'),
          ),
        ),
      ],
    ]);
  }
}

// ---------- карточки ----------
class _Cards extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _Cards({required this.items});
  @override
  State<_Cards> createState() => _CardsState();
}

class _CardsState extends State<_Cards> {
  final _page = PageController(viewportFraction: .88);
  final _flipped = <int>{};
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Column(children: [
      const SizedBox(height: 8),
      Text('${_i + 1} / ${widget.items.length} · нажмите, чтобы перевернуть', style: TextStyle(color: s.muted, fontSize: 13)),
      Expanded(
        child: PageView.builder(
          controller: _page,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) {
            final c = widget.items[i];
            final back = _flipped.contains(i);
            return GestureDetector(
              onTap: () => setState(() => back ? _flipped.remove(i) : _flipped.add(i)),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: back ? 1 : 0),
                duration: const Duration(milliseconds: 350),
                builder: (_, v, __) {
                  final showBack = v > .5;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, .001)
                      ..rotateY(math.pi * v),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(showBack ? math.pi : 0),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: showBack ? s.heroBorder : s.border),
                          gradient: showBack ? LinearGradient(colors: [s.heroStart, s.card], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                          color: showBack ? null : s.card,
                        ),
                        alignment: Alignment.center,
                        child: SingleChildScrollView(
                          child: Text(showBack ? '${c['back'] ?? ''}' : '${c['front'] ?? ''}',
                              textAlign: TextAlign.center,
                              style: showBack
                                  ? TextStyle(color: s.text, fontSize: 17, height: 1.45)
                                  : display(20, color: s.text)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

// ---------- билеты ----------
class _TicketAnswers extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _TicketAnswers({required this.items});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final missing = items.where((t) => t['found'] == false).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(missing == 0 ? 'Ответы найдены на все билеты' : 'Нет в записях: $missing из ${items.length} — их нужно взять из учебника',
            style: TextStyle(color: missing == 0 ? s.success : s.warn, fontWeight: FontWeight.w700)),
      ),
      for (final t in items)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: s.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t['found'] == false ? s.warn.withValues(alpha: .6) : s.border),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              shape: const RoundedRectangleBorder(),
              leading: Icon(t['found'] == false ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                  color: t['found'] == false ? s.warn : s.success),
              title: Text('${t['ticket'] ?? ''}', style: TextStyle(color: s.text, fontWeight: FontWeight.w700)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('${t['answer'] ?? ''}', style: TextStyle(color: s.text, height: 1.45)),
                if ((t['sources'] as List?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Источники: ${(t['sources'] as List).join('; ')}', style: TextStyle(color: s.muted, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
    ]);
  }
}
