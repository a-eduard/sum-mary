import 'package:flutter/material.dart';

import '../config.dart';
import '../services/billing.dart';
import '../services/repo.dart';
import '../theme.dart';

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
    final sel = _selected == id;
    return GestureDetector(
      onTap: () => setState(() => _selected = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? AppColors.accent : Colors.transparent, width: 2),
        ),
        child: Row(children: [
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.record, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge, style: const TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ]),
              Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          Text(_prices[id] ?? fallbackPrice, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const features = [
      (Icons.timer_outlined, '50 часов записи в месяц'),
      (Icons.people_outline, 'Расшифровка с разделением на спикеров'),
      (Icons.auto_awesome, 'Резюме, решения и задачи от Мари'),
      (Icons.chat_bubble_outline, 'Вопросы Мари по любой записи'),
      (Icons.computer, 'Программа для Windows'),
    ];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.workspace_premium, size: 64, color: AppColors.accent),
        const SizedBox(height: 12),
        const Text('СамМари Pro', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        for (final (icon, text) in features)
          ListTile(dense: true, leading: Icon(icon, color: AppColors.accent), title: Text(text)),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (!Billing.supported)
          const Text('Оформить подписку можно в Android-приложении из RuStore.', textAlign: TextAlign.center)
        else if (!_available)
          const Text('Покупки недоступны: установите RuStore и войдите в него.', textAlign: TextAlign.center)
        else ...[
          _plan(AppConfig.proYearId, 'На год', '3 490 ₽', '≈ 290 ₽ в месяц', badge: '−40%'),
          _plan(AppConfig.proMonthId, 'На месяц', '490 ₽', 'Отмена в любой момент'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _buy,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: _busy ? const CircularProgressIndicator() : const Text('Оформить подписку'),
          ),
          const SizedBox(height: 8),
          const Text('Подписка продлевается автоматически. Отменить можно в RuStore → Профиль → Подписки.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ]),
    );
  }
}
