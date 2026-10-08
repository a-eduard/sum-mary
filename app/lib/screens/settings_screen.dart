import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';
import '../roles.dart';
import '../services/billing.dart';
import '../services/device_storage.dart';
import '../services/repo.dart';
import '../theme.dart';
import 'notifications_screen.dart';
import 'onboarding_screen.dart';
import 'paywall_screen.dart';
import 'support_screen.dart';
import 'vocabulary_screen.dart';

/// Профиль: кто я, тариф, настройки, о приложении.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Profile> _profile = Billing.restore().catchError((_) {}).then((_) => Repo.profile());

  void _reload() {
    final f = Repo.profile();
    setState(() {
      _profile = f;
    });
  }

  void _onMe() {
    final p = Repo.me.value;
    if (p != null && mounted) {
      setState(() {
        _profile = Future.value(p);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    Repo.me.addListener(_onMe);
  }

  @override
  void dispose() {
    Repo.me.removeListener(_onMe);
    super.dispose();
  }

  Future<void> _editName(Profile p) async {
    final name = TextEditingController(text: p.displayName ?? '');
    final aliases = TextEditingController(text: p.nameAliases.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Как вас зовут?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя')),
          const SizedBox(height: 10),
          TextField(controller: aliases,
              decoration: const InputDecoration(labelText: 'Как ещё обращаются', hintText: 'Эдик, Эдуард Альбертович')),
          const SizedBox(height: 8),
          Text('Мари отметит задачи, которые поручили лично вам.', style: TextStyle(color: context.sm.muted, fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final m = ScaffoldMessenger.of(context);
      try {
        await Repo.saveName(name.text, aliases.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
        m.showSnackBar(const SnackBar(content: Text('Имя сохранено')));
      } catch (e) {
        m.showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return FutureBuilder<Profile>(
      future: _profile,
      builder: (context, snap) {
        final p = snap.data;
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Нет связи с сервером', style: TextStyle(color: s.muted)),
              TextButton(onPressed: _reload, child: const Text('Повторить')),
            ]),
          );
        }
        if (p == null) return const Center(child: CircularProgressIndicator());
        final email = sb.auth.currentUser?.email ?? '';
        final name = (p.displayName?.trim().isNotEmpty ?? false) ? p.displayName!.trim() : email.split('@').first;
        final roleText = p.roles.map((r) => roleById(r).label).join(', ');
        return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 140), children: [
          // --- шапка
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.orbCyan, AppColors.orbViolet], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              alignment: Alignment.center,
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: display(26, color: const Color(0xFF0F1015))),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(20, color: s.text)),
                const SizedBox(height: 2),
                Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.muted, fontSize: 13)),
                const SizedBox(height: 6),
                _Badge(p.isAdmin ? 'Тестировщик' : (p.isPro ? 'Pro' : 'Бесплатный тариф'),
                    p.isAdmin || p.isPro ? s.accentText : s.muted),
              ]),
            ),
            IconButton(tooltip: 'Изменить имя', onPressed: () => _editName(p), icon: Icon(Icons.edit_rounded, color: s.muted)),
          ]),
          const SizedBox(height: 20),

          // --- тариф
          _Group(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p.isAdmin ? 'Тестирование · без лимита' : (p.isPro ? 'Pro · 50 часов в месяц' : 'Бесплатно · 30 минут в месяц'),
                      style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 16))),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.isAdmin ? 0 : (p.minutesUsed / p.effectiveLimit).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    color: s.accent,
                    backgroundColor: s.border,
                  ),
                ),
                const SizedBox(height: 8),
                Text(p.isAdmin ? 'Использовано ${p.minutesUsed} мин в этом месяце'
                    : 'Использовано ${p.minutesUsed} из ${p.effectiveLimit} мин в этом месяце',
                    style: TextStyle(color: s.muted, fontSize: 13)),
                if (!p.isPro && !p.isAdmin) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
                        _reload();
                      },
                      child: const Text('Перейти на Pro'),
                    ),
                  ),
                ],
              ]),
            ),
          ]),

          if (p.isAdmin) ...[
            _Header('Режим тестировщика'),
            _Group(children: [
              _Item(Icons.swap_horiz_rounded, 'Сменить роль', 'Сейчас: ${roleText.isEmpty ? 'не выбрана' : roleText}',
                  () => Navigator.push(context, MaterialPageRoute(
                      builder: (ctx) => OnboardingScreen(fromSettings: true, onDone: () => Navigator.pop(ctx))))
                      .then((_) => _reload())),
              _Item(Icons.restart_alt_rounded, 'Показать знакомство заново', 'Откроется при следующем запуске', () async {
                await sb.from('profiles').update({'onboarded': false}).eq('id', Repo.uid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Перезапустите приложение — откроется знакомство')));
                }
              }),
              _Item(Icons.workspace_premium_rounded, 'Экран подписки', null,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()))),
            ]),
          ],

          _Header('Настройки'),
          _Group(children: [
            _Item(Icons.badge_outlined, 'Имя', p.displayName ?? 'Не указано', () => _editName(p)),
            _Item(Icons.person_search_rounded, 'Роль и полки', roleText.isEmpty ? 'Не выбрано' : roleText,
                () => Navigator.push(context, MaterialPageRoute(
                    builder: (ctx) => OnboardingScreen(fromSettings: true, onDone: () => Navigator.pop(ctx))))
                    .then((_) => _reload())),
            _Item(Icons.notifications_none_rounded, 'Уведомления', 'Что присылать и во сколько',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
            ValueListenableBuilder<int>(
              valueListenable: DeviceStorage.keepDays,
              builder: (_, d, __) => _Item(Icons.sd_storage_outlined, 'Память телефона',
                  d < 0 ? 'Аудио хранится всегда' : 'Аудио удаляется через $d дн. после обработки',
                  () => showStorageSheet(context)),
            ),
            _Item(Icons.spellcheck_rounded, 'Словарь терминов', 'Имена и термины — Мари напишет их правильно',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VocabularyScreen()))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(children: [
                Icon(Icons.palette_outlined, color: s.accentText),
                const SizedBox(width: 16),
                Expanded(child: Text('Тема', style: TextStyle(color: s.text, fontWeight: FontWeight.w600, fontSize: 16))),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController.mode,
                  builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Авто')),
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18)),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => ThemeController.set(v.first),
                  ),
                ),
              ]),
            ),
          ]),

          _Header('Помощь'),
          _Group(children: [
            _Item(Icons.call_rounded, 'Как записывать звонки', null, () => showDialog(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('Запись звонков'),
                    content: Text('1. В приложении «Телефон» включите автоматическую запись вызовов.\n\n'
                        '2. После звонка на главной нажмите «Звонок» и выберите файл записи.\n\n'
                        'Обычно записи лежат в папке Music/Recordings/Call Recordings. '
                        'Предупреждайте собеседника о записи разговора.'),
                  ),
                )),
            _Item(Icons.support_agent_rounded, 'Написать в поддержку', 'Ответим здесь и на почту',
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()))),
            _Item(Icons.privacy_tip_outlined, 'Политика конфиденциальности', null, () => launchUrl(Uri.parse(AppConfig.privacyUrl))),
            _Item(Icons.description_outlined, 'Пользовательское соглашение', null, () => launchUrl(Uri.parse(AppConfig.termsUrl))),
          ]),
          const SizedBox(height: 16),
          _Group(children: [
            _Item(Icons.logout_rounded, 'Выйти', null, () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Выйти из аккаунта?'),
                  content: const Text('Записи сохранятся — войдите снова по email.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
                  ],
                ),
              );
              if (ok == true) await sb.auth.signOut();
            }, danger: true),
          ]),
          const SizedBox(height: 16),
          Center(child: Text('СамМари · версия 1.0', style: TextStyle(color: s.muted, fontSize: 12))),
        ]);
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Text(text, style: display(13, color: context.sm.muted, weight: FontWeight.w500)),
      );
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Container(
      decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 56, color: s.border),
          children[i],
        ],
      ]),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final bool danger;
  const _Item(this.icon, this.title, this.sub, this.onTap, {this.danger = false});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return ListTile(
      leading: Icon(icon, color: danger ? s.danger : s.accentText),
      title: Text(title, style: TextStyle(color: danger ? s.danger : s.text, fontWeight: FontWeight.w600)),
      subtitle: sub == null ? null : Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.muted)),
      trailing: danger ? null : Icon(Icons.chevron_right_rounded, color: s.muted),
      onTap: onTap,
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

/// «Память телефона»: сколько занимают записи, сколько свободно, как долго хранить аудио.
Future<void> showStorageSheet(BuildContext context) async {
  final used = await DeviceStorage.usedBytes();
  final free = await DeviceStorage.freeBytes();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final s = ctx.sm;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: ValueListenableBuilder<int>(
            valueListenable: DeviceStorage.keepDays,
            builder: (ctx, days, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Память телефона', style: display(18, color: s.text)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _Stat('Записи СамМари', DeviceStorage.fmt(used))),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat('Свободно',
                      free == null ? '—' : '${DeviceStorage.fmt(free)} · ≈${DeviceStorage.hoursLeft(free).floor()} ч записи'),
                ),
              ]),
              const SizedBox(height: 16),
              Text('Час записи занимает около 15 МБ. Итоги, расшифровки и фото доски хранятся в облаке — '
                  'с телефона удаляется только аудио, а плеер у старых записей пропадает.',
                  style: TextStyle(color: s.muted, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              Text('Хранить аудио на телефоне', style: TextStyle(color: s.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (d, label) in const [(7, '7 дней'), (30, '30 дней'), (90, '3 месяца'), (-1, 'Всегда')])
                  ChoiceChip(
                    label: Text(label),
                    selected: days == d,
                    onSelected: (_) => DeviceStorage.setKeepDays(d),
                  ),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Удалить аудио обработанных записей'),
                  onPressed: () async {
                    final freed = await DeviceStorage.cleanup(await Repo.recordings().first, days: 0);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Освобождено ${DeviceStorage.fmt(freed)}')));
                    }
                  },
                ),
              ),
            ]),
          ),
        ),
      );
    },
  );
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: s.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: s.text, fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    );
  }
}
