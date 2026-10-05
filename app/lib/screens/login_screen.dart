import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme.dart';

/// Вход по email: отправляем 6-значный код, пользователь вводит его.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false, _busy = false;
  String? _error;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Введите email');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithOtp(email: email, shouldCreateUser: true);
      setState(() => _codeSent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyOTP(type: OtpType.email, email: _email.text.trim(), token: _code.text.trim());
    } on AuthException catch (_) {
      setState(() => _error = 'Неверный или устаревший код');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.graphic_eq, size: 64, color: AppColors.accent),
                const SizedBox(height: 12),
                const Text('СамМари', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Мари запишет встречу, звонок или лекцию,\nрасшифрует и выделит главное',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(hintText: 'Код из письма', prefixIcon: Icon(Icons.pin_outlined)),
                  ),
                ],
                if (_error != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.record)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : (_codeSent ? _verify : _send),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_codeSent ? 'Войти' : 'Получить код'),
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: () => setState(() {
                      _codeSent = false;
                      _code.clear();
                    }),
                    child: const Text('Изменить email'),
                  ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(AppConfig.privacyUrl)),
                  child: const Text('Продолжая, вы принимаете политику конфиденциальности',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
