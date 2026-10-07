import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:intl/intl.dart';

import '../models.dart';

/// Календарь телефона (Google, Яндекс — какой подключён): открываем готовое событие,
/// пользователь проверяет дату и сохраняет.
class CalendarService {
  static Future<bool> add(EventItem e, {String? recordingTitle}) {
    final allDay = e.time == null;
    final start = e.start;
    final end = allDay ? start.add(const Duration(days: 1)) : start.add(const Duration(hours: 1));
    return Add2Calendar.addEvent2Cal(Event(
      title: e.title,
      description: recordingTitle == null ? 'Из записи СамМари' : 'Из записи «$recordingTitle» — СамМари',
      startDate: start,
      endDate: end,
      allDay: allDay,
      androidParams: const AndroidParams(),
    ));
  }
}

/// «завтра, 10:00», «чт, 15 окт.»
String fmtEventDate(EventItem e) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = e.date.difference(today).inDays;
  final day = switch (d) {
    0 => 'сегодня',
    1 => 'завтра',
    2 => 'послезавтра',
    _ => DateFormat('E, d MMM', 'ru').format(e.date),
  };
  return e.time == null ? day : '$day, ${e.time}';
}
