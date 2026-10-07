import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'uploader.dart';

SupabaseClient get sb => Supabase.instance.client;

/// Всё общение с базой Supabase.
class Repo {
  static String get uid => sb.auth.currentUser!.id;

  /// Живой поток, который сам восстанавливается: после сна телефона, смены сети или VPN
  /// токен мог истечь — обновляем сессию и переподписываемся, не показывая ошибку.
  static Stream<T> _live<T>(Stream<T> Function() make) async* {
    var delay = 1;
    while (true) {
      try {
        await for (final v in make()) {
          delay = 1;
          yield v;
        }
        return;
      } catch (_) {
        try {
          await sb.auth.refreshSession();
        } catch (_) {}
        await Future.delayed(Duration(seconds: delay));
        delay = delay >= 16 ? 30 : delay * 2;
      }
    }
  }

  // ---------- записи ----------
  static Stream<List<Recording>> recordings() => _live(() => sb
      .from('recordings')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('recorded_at', ascending: false)
      .map((rows) => rows.where((r) => r['deleted_at'] == null).map(Recording.fromMap).toList()));

  static Stream<Recording?> recording(String id) => _live(() => sb
      .from('recordings')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Recording.fromMap(rows.first)));

  static Future<List<Recording>> search(String q) async {
    final rows = await sb.rpc('search_recordings', params: {'q': q});
    return (rows as List).map((r) => Recording.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  static Future<String> createRecording(
      {required String source, required String localPath, String mode = 'meeting', String? folderId, int? durationSec,
      List<Map<String, dynamic>> marks = const []}) async {
    final row = await sb
        .from('recordings')
        .insert({
          'source': source,
          'mode': mode,
          'folder_id': folderId,
          'marks': marks,
          'tz_offset_min': DateTime.now().timeZoneOffset.inMinutes,
          'local_audio': localPath,
          'duration_sec': durationSec,
          'status': 'uploading',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Загружает аудио (кусками, с докачкой) и ставит запись в очередь на обработку.
  static Future<void> uploadAndQueue(String recordingId, File file) => Uploader.start(recordingId, file.path);

  /// Записи, которые не успели загрузиться (для докачки после запуска).
  static Future<List<Recording>> pendingUploads() async {
    final rows = await sb.from('recordings').select().eq('status', 'uploading').isFilter('deleted_at', null);
    return rows.map(Recording.fromMap).toList();
  }

  static Future<void> updateLocalPath(String id, String path) =>
      sb.from('recordings').update({'local_audio': path}).eq('id', id);
  static Future<void> rename(String id, String title) => sb.from('recordings').update({'title': title}).eq('id', id);
  static Future<void> setFavorite(String id, bool v) => sb.from('recordings').update({'favorite': v}).eq('id', id);
  static Future<void> setSpeakerNames(String id, Map<String, String> names) =>
      sb.from('recordings').update({'speaker_names': names}).eq('id', id);
  static Future<void> delete(String id) =>
      sb.from('recordings').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  static Future<List<Segment>> segments(String id) async {
    final rows = await sb.from('segments').select().eq('recording_id', id).order('idx');
    return rows.map(Segment.fromMap).toList();
  }

  static Future<Summary?> summary(String id) async {
    final row = await sb.from('summaries').select().eq('recording_id', id).maybeSingle();
    return row == null ? null : Summary.fromMap(row);
  }

  /// Ближайшие события из всех записей (контрольные, встречи, дедлайны).
  static Future<List<EventItem>> upcomingEvents() async {
    final rows = await sb
        .from('summaries')
        .select('recording_id, events, recordings!inner(deleted_at)')
        .isFilter('recordings.deleted_at', null);
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final out = <EventItem>[];
    for (final r in rows) {
      for (final e in (r['events'] as List? ?? [])) {
        try {
          final ev = EventItem.fromMap(Map<String, dynamic>.from(e), r['recording_id']);
          if (!ev.date.isBefore(start)) out.add(ev);
        } catch (_) {}
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// Убрать событие из «Ближайшего» (удаляется из итога записи).
  static Future<void> dismissEvent(EventItem e) async {
    final row = await sb.from('summaries').select('events').eq('recording_id', e.recordingId).maybeSingle();
    if (row == null) return;
    final events = List<Map<String, dynamic>>.from((row['events'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)));
    events.removeWhere((x) => '${x['title']}' == e.title && '${x['date']}'.startsWith(DateFormat('yyyy-MM-dd').format(e.date)));
    await sb.from('summaries').update({'events': events}).eq('recording_id', e.recordingId);
  }

  // ---------- задачи ----------
  static Stream<List<TaskItem>> tasks() => _live(() => sb
      .from('tasks')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(TaskItem.fromMap).toList()));

  static Future<void> setTaskDone(String id, bool done) => sb.from('tasks').update({'done': done}).eq('id', id);
  static Future<void> addTask(String text, {String? recordingId, bool forMe = true}) =>
      sb.from('tasks').insert({'text': text, 'recording_id': recordingId, 'for_me': forMe});
  static Future<void> deleteTask(String id) => sb.from('tasks').delete().eq('id', id);

  // ---------- полки ----------
  static final folders = ValueNotifier<List<Folder>>([]);

  static Future<List<Folder>> loadFolders() async {
    final rows = await sb.from('folders').select().order('sort').order('created_at');
    folders.value = rows.map(Folder.fromMap).toList();
    return folders.value;
  }

  static Future<void> createFolders(List<(String name, String color, String kind)> items) async {
    if (items.isEmpty) return;
    await sb.from('folders').insert([
      for (var i = 0; i < items.length; i++) {'name': items[i].$1, 'color': items[i].$2, 'kind': items[i].$3, 'sort': i},
    ]);
    await loadFolders();
  }

  static Future<void> addFolder(String name, String color, {String kind = 'other'}) async {
    await sb.from('folders').insert({'name': name, 'color': color, 'kind': kind, 'sort': folders.value.length});
    await loadFolders();
  }

  static Future<void> deleteFolder(String id) async {
    await sb.from('folders').delete().eq('id', id);
    await loadFolders();
  }

  static Future<void> moveToFolder(String recordingId, String? folderId) =>
      sb.from('recordings').update({'folder_id': folderId, 'suggested_folder_id': null}).eq('id', recordingId);

  static Future<void> saveName(String name, List<String> aliases) =>
      sb.from('profiles').update({'display_name': name.trim(), 'name_aliases': aliases}).eq('id', uid);

  static Future<void> saveOnboarding({required List<String> roles, int? grade, required String defaultMode}) =>
      sb.from('profiles').update({'roles': roles, 'grade': grade, 'default_mode': defaultMode, 'onboarded': true}).eq('id', uid);

  // ---------- профиль и словарь ----------
  static Future<Profile> profile() async =>
      Profile.fromMap(await sb.from('profiles').select().eq('id', uid).single());

  static Future<List<Map<String, dynamic>>> vocabulary() async =>
      await sb.from('vocabulary').select().order('created_at');
  static Future<void> addTerm(String term) => sb.from('vocabulary').insert({'term': term.trim()});
  static Future<void> deleteTerm(String id) => sb.from('vocabulary').delete().eq('id', id);
}
