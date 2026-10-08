import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';

/// Переписка с поддержкой. Сообщение уходит владельцу в Telegram, ответ приходит сюда и на почту.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final Stream<List<SupportMsg>> _stream = Repo.support();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  int _seen = 0;

  static const _topics = ['Запись не загружается', 'Неточная расшифровка', 'Вопрос по оплате', 'Идея для Мари'];

  @override
  void initState() {
    super.initState();
    Repo.markSupportRead().catchError((_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Api.support(text, appVersion: AppConfig.version, device: 'Android ${Platform.operatingSystemVersion}');
      _input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не отправилось: ${'$e'.replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
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
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Поддержка', style: display(17, color: s.text)),
            Text('Отвечаем обычно в течение дня', style: TextStyle(color: s.muted, fontSize: 12)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<SupportMsg>>(
            stream: _stream,
            builder: (context, snap) {
              final list = snap.data ?? const <SupportMsg>[];
              if (list.length != _seen) {
                if (list.any((m) => !m.fromMe && m.readAt == null)) Repo.markSupportRead().catchError((_) {});
                _seen = list.length;
                _toBottom();
              }
              if (!snap.hasData && !snap.hasError) return const Center(child: CircularProgressIndicator());
              if (list.isEmpty) return _empty(s);
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final m = list[i];
                  final newDay = i == 0 || !DateUtils.isSameDay(list[i - 1].createdAt, m.createdAt);
                  return Column(children: [
                    if (newDay)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(DateFormat('d MMMM', 'ru').format(m.createdAt), style: TextStyle(color: s.muted, fontSize: 12)),
                      ),
                    _Msg(m: m),
                  ]);
                },
              );
            },
          ),
        ),
        _composer(s),
      ]),
    );
  }

  Widget _empty(Sm s) => ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
        const Center(child: MariOrb(size: 88)),
        const SizedBox(height: 20),
        Text('Чем помочь?', textAlign: TextAlign.center, style: display(20, color: s.text)),
        const SizedBox(height: 8),
        Text('Напишите вопрос, ошибку или идею — сообщение сразу получит команда СамМари. '
            'Ответ придёт сюда и на вашу почту.',
            textAlign: TextAlign.center, style: TextStyle(color: s.muted, height: 1.45)),
        const SizedBox(height: 20),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final t in _topics)
            ActionChip(
              label: Text(t),
              onPressed: () {
                _input.text = '$t: ';
                _input.selection = TextSelection.collapsed(offset: _input.text.length);
              },
            ),
        ]),
      ]);

  Widget _composer(Sm s) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: s.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 6,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Сообщение', counterText: '', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Отправить',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ]),
        ),
      );
}

class _Msg extends StatelessWidget {
  final SupportMsg m;
  const _Msg({required this.m});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final mine = m.fromMe;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: mine ? s.accent : s.card,
          border: mine ? null : Border.all(color: s.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (!mine)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Команда СамМари', style: TextStyle(color: s.accentText, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(m.text, style: TextStyle(color: mine ? s.onAccent : s.text, height: 1.4, fontSize: 15)),
          ),
          const SizedBox(height: 2),
          Text(DateFormat('HH:mm').format(m.createdAt),
              style: TextStyle(color: (mine ? s.onAccent : s.muted).withValues(alpha: .7), fontSize: 11)),
        ]),
      ),
    );
  }
}
