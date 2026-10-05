import 'package:flutter/material.dart';

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
  String? _price;
  bool _available = false, _busy = false;

  @override
  void initState() {
    super.initState();
    () async {
      final a = await Billing.available();
      final p = a ? await Billing.priceLabel() : null;
      if (mounted) {
        setState(() {
          _available = a;
          _price = p;
        });
      }
    }();
  }

  Future<void> _buy() async {
    setState(() => _busy = true);
    try {
      final ok = await Billing.buyPro(userId: Repo.uid, email: sb.auth.currentUser?.email);
      if (ok && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Оплата не прошла: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const features = [
      (Icons.all_inclusive, 'Безлимитные записи встреч, лекций и звонков'),
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
        const SizedBox(height: 24),
        for (final (icon, text) in features)
          ListTile(leading: Icon(icon, color: AppColors.accent), title: Text(text)),
        const SizedBox(height: 24),
        if (!Billing.supported)
          const Text('Оформить подписку можно в Android-приложении из RuStore.', textAlign: TextAlign.center)
        else if (!_available)
          const Text('Покупки недоступны: установите RuStore и войдите в него.', textAlign: TextAlign.center)
        else
          FilledButton(
            onPressed: _busy ? null : _buy,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: _busy
                ? const CircularProgressIndicator()
                : Text(_price == null ? 'Оформить подписку' : 'Оформить за $_price в месяц'),
          ),
      ]),
    );
  }
}
