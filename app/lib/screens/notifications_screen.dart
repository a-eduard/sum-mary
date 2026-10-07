import 'package:flutter/material.dart';

import '../services/notifications.dart';
import '../theme.dart';

/// Настройки уведомлений: что присылать и во сколько.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления')),
      body: ValueListenableBuilder<NotifSettings>(
        valueListenable: Notifications.settings,
        builder: (context, n, _) {
          void set(void Function(NotifSettings) f) {
            f(n);
            Notifications.save(n);
          }

          Widget sw(String title, String sub, bool v, void Function(bool) on, IconData icon) => SwitchListTile(
                secondary: Icon(icon, color: s.accentText),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(sub, style: TextStyle(color: s.muted, height: 1.3)),
                value: v,
                onChanged: on,
              );

          Widget hour(String title, int value, List<int> options, void Function(int) on) => ListTile(
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: DropdownButton<int>(
                  value: value,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: [for (final h in options) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                  onChanged: (v) => v == null ? null : on(v),
                ),
              );

          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            Card(
              child: Column(children: [
                sw('Итог готов', 'Когда Мари закончила разбирать запись', n.ready, (v) => set((x) => x.ready = v),
                    Icons.auto_awesome_rounded),
                sw('Контрольные и экзамены', 'Накануне вечером — «повторим?», утром — «удачи»', n.tests,
                    (v) => set((x) => x.tests = v), Icons.school_rounded),
                sw('Встречи и созвоны', 'За час до встречи — что обсуждали в прошлый раз', n.meetings,
                    (v) => set((x) => x.meetings = v), Icons.groups_rounded),
                sw('Сроки моих задач', 'Накануне и утром в день срока', n.deadlines, (v) => set((x) => x.deadlines = v),
                    Icons.task_alt_rounded),
                sw('Утренняя сводка', 'План на день: события и задачи', n.digest, (v) => set((x) => x.digest = v),
                    Icons.wb_sunny_rounded),
              ]),
            ),
            Card(
              child: Column(children: [
                hour('Утренние уведомления', n.morningHour, const [6, 7, 8, 9, 10], (v) => set((x) => x.morningHour = v)),
                hour('Вечерние напоминания', n.eveningHour, const [17, 18, 19, 20, 21, 22], (v) => set((x) => x.eveningHour = v)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text('Даты Мари находит в ваших записях: «контрольная в четверг», «созвон завтра в 15:00». '
                  'Убрать ненужное событие можно на главном экране.',
                  style: TextStyle(color: s.muted, fontSize: 13, height: 1.4)),
            ),
          ]);
        },
      ),
    );
  }
}
