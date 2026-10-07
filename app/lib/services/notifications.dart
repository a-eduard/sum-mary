import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

/// Какие уведомления присылать — выбирает пользователь в профиле.
class NotifSettings {
  bool ready, tests, meetings, deadlines, digest;
  int morningHour, eveningHour;
  NotifSettings({
    this.ready = true,
    this.tests = true,
    this.meetings = true,
    this.deadlines = true,
    this.digest = false,
    this.morningHour = 8,
    this.eveningHour = 19,
  });
}

/// Умные уведомления: «итог готов», контрольные, встречи, сроки задач, утренняя сводка.
/// Всё планируется на телефоне — работает без интернета и после перезагрузки.
class Notifications {
  static final _p = FlutterLocalNotificationsPlugin();
  static final settings = ValueNotifier(NotifSettings());
  /// Нажали на уведомление записи — главный экран откроет эту запись.
  static final openRecording = ValueNotifier<String?>(null);
  static bool _ready = false;

  static const _channelReady = AndroidNotificationDetails('ready', 'Итог готов',
      channelDescription: 'Мари закончила разбирать запись', importance: Importance.high, priority: Priority.high);
  static const _channelRemind = AndroidNotificationDetails('remind', 'Напоминания',
      channelDescription: 'Контрольные, встречи, сроки задач', importance: Importance.high, priority: Priority.high);
  static const _channelDigest = AndroidNotificationDetails('digest', 'Утренняя сводка',
      channelDescription: 'План на день', importance: Importance.defaultImportance);

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _p.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) openRecording.value = id;
      },
    );
    final launch = await _p.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null && payload.isNotEmpty) openRecording.value = payload;
    await _load();
    _ready = true;
  }

  static Future<void> askPermission() async {
    if (await Permission.notification.isDenied) await Permission.notification.request();
  }

  static Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    settings.value = NotifSettings(
      ready: p.getBool('n_ready') ?? true,
      tests: p.getBool('n_tests') ?? true,
      meetings: p.getBool('n_meetings') ?? true,
      deadlines: p.getBool('n_deadlines') ?? true,
      digest: p.getBool('n_digest') ?? false,
      morningHour: p.getInt('n_morning') ?? 8,
      eveningHour: p.getInt('n_evening') ?? 19,
    );
  }

  static Future<void> save(NotifSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('n_ready', s.ready);
    await p.setBool('n_tests', s.tests);
    await p.setBool('n_meetings', s.meetings);
    await p.setBool('n_deadlines', s.deadlines);
    await p.setBool('n_digest', s.digest);
    await p.setInt('n_morning', s.morningHour);
    await p.setInt('n_evening', s.eveningHour);
    settings.value = NotifSettings(
        ready: s.ready, tests: s.tests, meetings: s.meetings, deadlines: s.deadlines, digest: s.digest,
        morningHour: s.morningHour, eveningHour: s.eveningHour);
    await reschedule(_lastEvents, _lastTasks);
  }

  /// «Итог готов» — сразу.
  static Future<void> recordingReady(Recording r) async {
    if (!_ready || !settings.value.ready) return;
    await _p.show(r.id.hashCode & 0x7fffffff, 'Итог готов', r.title,
        const NotificationDetails(android: _channelReady), payload: r.id);
  }

  static List<EventItem> _lastEvents = [];
  static List<TaskItem> _lastTasks = [];

  /// Перепланировать все напоминания (вызывается при изменении событий, задач или настроек).
  static Future<void> reschedule(List<EventItem> events, List<TaskItem> tasks) async {
    _lastEvents = events;
    _lastTasks = tasks;
    if (!_ready) return;
    for (final r in await _p.pendingNotificationRequests()) {
      await _p.cancel(r.id);
    }
    final s = settings.value;
    final now = DateTime.now();
    var n = 0;
    Future<void> at(DateTime when, String title, String body, String? payload, AndroidNotificationDetails ch) async {
      if (!when.isAfter(now) || n >= 60) return; // у Android есть лимит на запланированные
      n++;
      await _p.zonedSchedule(
        (title + body + when.toIso8601String()).hashCode & 0x7fffffff,
        title,
        body,
        tz.TZDateTime.from(when.toUtc(), tz.UTC),
        NotificationDetails(android: ch),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }

    DateTime dayAt(DateTime d, int hour) => DateTime(d.year, d.month, d.day, hour);
    String timeOf(EventItem e) => e.time == null ? '' : ' в ${e.time}';

    for (final e in events) {
      final study = e.kind == 'test' || e.kind == 'homework';
      if (study && s.tests) {
        await at(dayAt(e.date.subtract(const Duration(days: 1)), s.eveningHour), 'Завтра: ${e.title}',
            'Повторим? Откройте конспект и пройдите тест', e.recordingId, _channelRemind);
        await at(dayAt(e.date, s.morningHour), 'Сегодня${timeOf(e)}: ${e.title}', 'Удачи! Конспект — в СамМари',
            e.recordingId, _channelRemind);
      } else if (e.kind == 'meeting' && s.meetings) {
        if (e.time != null) {
          await at(e.start.subtract(const Duration(hours: 1)), 'Через час: ${e.title}',
              'Посмотрите, о чём договорились в прошлый раз', e.recordingId, _channelRemind);
        } else {
          await at(dayAt(e.date, s.morningHour), 'Сегодня: ${e.title}', 'Из записи в СамМари', e.recordingId, _channelRemind);
        }
      } else if (s.deadlines && !study && e.kind != 'meeting') {
        await at(dayAt(e.date.subtract(const Duration(days: 1)), s.eveningHour), 'Завтра: ${e.title}',
            'Напоминание из записи', e.recordingId, _channelRemind);
      }
    }
    if (s.deadlines) {
      for (final t in tasks.where((t) => !t.done && t.forMe && t.dueDate != null)) {
        await at(dayAt(t.dueDate!.subtract(const Duration(days: 1)), s.eveningHour), 'Срок завтра', t.text,
            t.recordingId, _channelRemind);
        await at(dayAt(t.dueDate!, s.morningHour), 'Срок сегодня', t.text, t.recordingId, _channelRemind);
      }
    }
    if (s.digest) {
      for (var i = 0; i < 7; i++) {
        final d = DateTime(now.year, now.month, now.day).add(Duration(days: i));
        final ev = events.where((e) => e.date == d).map((e) => e.title).toList();
        final ts = tasks.where((t) => !t.done && t.forMe && t.dueDate == d).length;
        final parts = [if (ev.isNotEmpty) ev.join(', '), if (ts > 0) 'задач на сегодня: $ts'];
        await at(dayAt(d, s.morningHour), 'Доброе утро! План на сегодня',
            parts.isEmpty ? 'Ничего срочного — хорошего дня' : parts.join(' · '), null, _channelDigest);
      }
    }
  }
}
