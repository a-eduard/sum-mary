import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';

/// Чат с Мари: по одной записи, по полке или по всем записям.
class ChatScreen extends StatefulWidget {
  final Recording? recording;
  final Folder? folder;
  const ChatScreen({super.key, this.recording, this.folder});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgs = <Map<String, String>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  String get _scopeTitle => widget.recording?.title ?? (widget.folder != null ? 'Полка «${widget.folder!.name}»' : 'Все записи');

  List<String> get _suggestions {
    final m = widget.recording?.mode;
    if (widget.recording != null && (m == 'lesson' || m == 'lecture' || m == 'seminar' || m == 'tutor')) {
      return ['Объясни главное простыми словами', 'Сделай 5 вопросов для самопроверки', 'Что будет на контрольной?', 'Какое домашнее задание?'];
    }
    if (widget.recording != null) {
      return ['Какие задачи на мне?', 'Какие решения приняли?', 'Составь письмо участникам по итогам', 'О чём договорились по срокам?'];
    }
    return [
      'Что мне нужно сделать на этой неделе?',
      'Какие контрольные и встречи впереди?',
      'Сделай тест по последним урокам',
      'Что обещали клиентам?',
    ];
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    _input.clear();
    final history = List<Map<String, String>>.from(_msgs);
    setState(() {
      _msgs.add({'role': 'user', 'content': q});
      _busy = true;
    });
    _toEnd();
    try {
      final a = await Api.chat(q, history, recordingId: widget.recording?.id, folderId: widget.folder?.id);
      _msgs.add({'role': 'assistant', 'content': a});
    } catch (e) {
      _msgs.add({'role': 'assistant', 'content': 'Не получилось ответить: $e', 'error': '1'});
    }
    if (mounted) setState(() => _busy = false);
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          const MariOrb(size: 34, glow: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Мари', style: display(16, color: s.text)),
              Text(_scopeTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.muted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? ListView(padding: const EdgeInsets.fromLTRB(20, 32, 20, 20), children: [
                  const Center(child: MariOrb(size: 96)),
                  const SizedBox(height: 20),
                  Text('Спросите что угодно', textAlign: TextAlign.center, style: display(20, color: s.text)),
                  const SizedBox(height: 8),
                  Text(
                      widget.recording != null
                          ? 'Я отвечу по этой записи и покажу, где это прозвучало.'
                          : 'Я найду ответ во всех ваших записях${widget.folder != null ? ' на этой полке' : ''} и скажу, откуда он.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: s.muted, height: 1.4)),
                  const SizedBox(height: 24),
                  for (final q in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(
                        onPressed: () => _send(q),
                        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16)),
                        child: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) return const _Typing();
                    final m = _msgs[i];
                    return _Bubble(text: m['content']!, mine: m['role'] == 'user', error: m['error'] != null);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Спросить Мари…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Отправить',
                onPressed: _busy ? null : _send,
                style: IconButton.styleFrom(backgroundColor: s.accent, foregroundColor: s.onAccent, minimumSize: const Size(52, 52)),
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine, error;
  const _Bubble({required this.text, required this.mine, this.error = false});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: mine ? s.accent : s.card,
          border: mine ? null : Border.all(color: error ? s.danger : s.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          SelectableText(text, style: TextStyle(color: mine ? s.onAccent : s.text, height: 1.45, fontSize: 15)),
          if (!mine && !error)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Скопировать',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
                },
                icon: Icon(Icons.copy_rounded, size: 16, color: s.muted),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: s.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const MariOrb(size: 18, glow: false),
          const SizedBox(width: 8),
          Text('Мари думает…', style: TextStyle(color: s.muted)),
        ]),
      ),
    );
  }
}
