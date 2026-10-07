import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';
import '../services/billing.dart';
import '../services/repo.dart';
import '../theme.dart';
import 'onboarding_screen.dart';
import 'paywall_screen.dart';
import 'vocabulary_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Profile> _profile = Billing.restore().then((_) => Repo.profile());

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 140), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
        child: Text('Профиль', style: display(24, color: context.sm.text)),
      ),
      FutureBuilder<Profile>(
        future: _profile,
        builder: (context, snap) {
          final p = snap.data;
          if (p == null) return const Card(child: ListTile(title: Text('Загрузка…')));
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.isPro ? 'Тариф Pro' : 'Бесплатный тариф',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                    value: (p.minutesUsed / p.effectiveLimit).clamp(0, 1).toDouble(),
                    minHeight: 8, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                Text(p.isAdmin ? 'Режим тестировщика: без лимита (использовано ${p.minutesUsed} мин)'
                    : 'Использовано ${p.minutesUsed} из ${p.effectiveLimit} мин в этом месяце',
                    style: TextStyle(color: context.sm.muted)),
                if (p.isAdmin) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Сменить роль'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (ctx) => OnboardingScreen(fromSettings: true, onDone: () => Navigator.pop(ctx)))),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Показать знакомство заново'),
                      onPressed: () async {
                        await sb.from('profiles').update({'onboarded': false}).eq('id', Repo.uid);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Перезапустите приложение — откроется выбор роли')));
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                      label: const Text('Экран подписки'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen())),
                    ),
                  ]),
                ],
                if (!p.isPro && !p.isAdmin) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
                      setState(() => _profile = Repo.profile());
                    },
                    child: const Text('Перейти на Pro — 50 часов в месяц'),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Оформление', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeController.mode,
              builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Авто')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                ],
                selected: {mode},
                onSelectionChanged: (v) => ThemeController.set(v.first),
              ),
            ),
          ]),
        ),
      ),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.person_search_rounded),
            title: const Text('Роль и полки'),
            subtitle: const Text('Кто вы и какие полки нужны'),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (ctx) => OnboardingScreen(fromSettings: true, onDone: () => Navigator.pop(ctx)))),
          ),
          ListTile(
            leading: const Icon(Icons.spellcheck),
            title: const Text('Словарь терминов'),
            subtitle: const Text('Имена, названия и термины — Мари будет писать их правильно'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VocabularyScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: const Text('Как записывать звонки'),
            onTap: () => showDialog(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('Запись звонков'),
                content: Text('1. Откройте приложение «Телефон» → Настройки → Запись вызовов и включите автоматическую запись.\n\n'
                    '2. После звонка откройте СамМари → кнопка «Импорт» вверху → «Запись телефонного звонка» и выберите файл.\n\n'
                    'Обычно записи лежат в папке Music/Recordings/Call Recordings. '
                    'Не забывайте предупреждать собеседника о записи разговора.'),
              ),
            ),
          ),
        ]),
      ),
      Card(
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(sb.auth.currentUser?.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Политика конфиденциальности'),
            onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Пользовательское соглашение'),
            onTap: () => launchUrl(Uri.parse(AppConfig.termsUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Выйти'),
            onTap: () => sb.auth.signOut(),
          ),
        ]),
      ),
    ]);
  }
}
