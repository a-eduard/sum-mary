import 'package:flutter/material.dart';

import '../config.dart';
import '../services/billing.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';

/// Экран подписки. Возвращает true, если подписка оформлена.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});
  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Map<String, String> _prices = {};
  bool _available = false, _loading = true, _busy = false;
  String _selected = AppConfig.proYearId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final a = await Billing.available();
    final p = a ? await Billing.prices() : <String, String>{};
    if (!mounted) return;
    setState(() {
      _available = a;
      _prices = p;
      _loading = false;
    });
  }

  Future<void> _buy() async {
    setState(() => _busy = true);
    try {
      final ok = await Billing.buyPro(productId: _selected, userId: Repo.uid, email: sb.auth.currentUser?.email);
      if (ok && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Оплата не прошла: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _plan(String id, String title, String fallbackPrice, String note, {String? badge}) {
    final s = context.sm;
    final sel = _selected == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: sel ? s.accent.withValues(alpha: context.isDark ? .18 : .1) : s.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22), side: BorderSide(color: sel ? s.accent : s.border, width: sel ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => setState(() => _selected = id),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sel ? s.accentText : s.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(title, style: TextStyle(color: s.text, fontSize: 17, fontWeight: FontWeight.w800)),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: s.accent, borderRadius: BorderRadius.circular(8)),
                        child: Text(badge, style: TextStyle(fontSize: 12, color: s.onAccent, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(note, style: TextStyle(color: s.muted, fontSize: 13)),
                ]),
              ),
              Text(_prices[id] ?? fallbackPrice, style: display(17, color: s.text)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    const features = [
      (Icons.timer_outlined, '50 часов записи в месяц', 'Лекции, уроки, встречи и звонки'),
      (Icons.auto_awesome_rounded, 'Цветной итог под каждый режим', 'Определения, формулы, важное, задачи'),
      (Icons.chat_bubble_outline_rounded, 'Чат с Мари по всем записям', 'Ответы со ссылкой на момент записи'),
      (Icons.event_available_rounded, 'Даты в календарь и напоминания', 'Контрольные, встречи, сроки'),
      (Icons.people_outline_rounded, 'Разделение на спикеров', 'Кто что сказал и кому что поручили'),
    ];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
        const Center(child: MariOrb(size: 96)),
        const SizedBox(height: 18),
        Text('СамМари Pro', textAlign: TextAlign.center, style: display(28, color: s.text)),
        const SizedBox(height: 6),
        Text('Мари слушает — вы учитесь и работаете', textAlign: TextAlign.center, style: TextStyle(color: s.muted)),
        const SizedBox(height: 22),
        for (final (icon, title, sub) in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: s.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: s.accentText, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: s.text, fontWeight: FontWeight.w700)),
                  Text(sub, style: TextStyle(color: s.muted, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (!Billing.supported)
          Text('Оформить подписку можно в Android-приложении из RuStore.', textAlign: TextAlign.center, style: TextStyle(color: s.muted))
        else if (!_available)
          Text('Покупки недоступны: установите RuStore и войдите в него.', textAlign: TextAlign.center, style: TextStyle(color: s.muted))
        else ...[
          _plan(AppConfig.proYearId, 'На год', '3 490 ₽', '≈ 290 ₽ в месяц', badge: '−40%'),
          _plan(AppConfig.proMonthId, 'На месяц', '490 ₽', 'Отмена в любой момент'),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: FilledButton(
              onPressed: _busy ? null : _buy,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Оформить подписку'),
            ),
          ),
          const SizedBox(height: 10),
          Text('Подписка продлевается автоматически. Отменить можно в RuStore → Профиль → Подписки.',
              textAlign: TextAlign.center, style: TextStyle(color: s.muted, fontSize: 12)),
        ],
      ]),
    );
  }
}
