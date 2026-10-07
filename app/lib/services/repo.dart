import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

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
      {required String source, required String localPath, String mode = 'meeting', int? durationSec, List<Map<String, dynamic>> marks = const []}) async {
    final row = await sb
        .from('recordings')
        .insert({
          'source': source,
          'mode': mode,
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

  /// Загружает аудио во временное хранилище и ставит запись в очередь на обработку.
  static Future<void> uploadAndQueue(String recordingId, File file) async {
    final ext = p.extension(file.path).isEmpty ? '.m4a' : p.extension(file.path);
    final path = '$uid/$recordingId$ext';
    await sb.storage.from('audio').upload(path, file, fileOptions: const FileOptions(upsert: true));
    await sb.from('recordings').update({'audio_path': path, 'status': 'queued'}).eq('id', recordingId);
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

  // ---------- задачи ----------
  static Stream<List<TaskItem>> tasks() => _live(() => sb
      .from('tasks')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(TaskItem.fromMap).toList()));

  static Future<void> setTaskDone(String id, bool done) => sb.from('tasks').update({'done': done}).eq('id', id);
  static Future<void> addTask(String text, {String? recordingId}) =>
      sb.from('tasks').insert({'text': text, 'recording_id': recordingId});
  static Future<void> deleteTask(String id) => sb.from('tasks').delete().eq('id', id);

  // ---------- профиль и словарь ----------
  static Future<Profile> profile() async =>
      Profile.fromMap(await sb.from('profiles').select().eq('id', uid).single());

  static Future<List<Map<String, dynamic>>> vocabulary() async =>
      await sb.from('vocabulary').select().order('created_at');
  static Future<void> addTerm(String term) => sb.from('vocabulary').insert({'term': term.trim()});
  static Future<void> deleteTerm(String id) => sb.from('vocabulary').delete().eq('id', id);
}
