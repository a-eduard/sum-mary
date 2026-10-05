import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';

/// Чат с Мари по одной записи.
class ChatScreen extends StatefulWidget {
  final Recording recording;
  const ChatScreen({super.key, required this.recording});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgs = <Map<String, String>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  static const _suggestions = [
    'Какие задачи на мне?',
    'Какие решения приняли?',
    'Составь письмо участникам по итогам',
    'О чём договорились по срокам?',
  ];

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
      final a = await Api.chat(widget.recording.id, q, history);
      _msgs.add({'role': 'assistant', 'content': a});
    } catch (e) {
      _msgs.add({'role': 'assistant', 'content': 'Не получилось ответить: $e'});
    }
    if (mounted) setState(() => _busy = false);
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мари'), bottom: PreferredSize(
        preferredSize: const Size.fromHeight(20),
        child: Text(widget.recording.title, style: const TextStyle(color: AppColors.muted), overflow: TextOverflow.ellipsis),
      )),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Привет! Я Мари. Спросите что угодно об этой записи.',
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                  ]),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _msgs.length + (_busy ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _msgs.length) {
                      return const Align(alignment: Alignment.centerLeft,
                          child: Padding(padding: EdgeInsets.all(12), child: Text('Мари думает…', style: TextStyle(color: AppColors.muted))));
                    }
                    final m = _msgs[i];
                    final me = m['role'] == 'user';
                    return Align(
                      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: me ? AppColors.accent : AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(m['content']!, style: const TextStyle(height: 1.4)),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Спросите Мари…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _busy ? null : _send, icon: const Icon(Icons.arrow_upward)),
            ]),
          ),
        ),
      ]),
    );
  }
}
