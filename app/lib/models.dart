class Recording {
  final String id;
  final String title;
  final String source;
  final String mode;
  final String status;
  final String? stage;
  final String? error;
  final String? localAudio;
  final int? durationSec;
  final Map<String, dynamic> speakerNames;
  final String? folderId;
  final String? suggestedFolderId;
  final bool favorite;
  final DateTime recordedAt;
  final DateTime? processedAt;

  Recording.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        title = m['title'] ?? 'Новая запись',
        source = m['source'] ?? 'mic',
        mode = m['mode'] ?? (m['source'] == 'call' ? 'call' : 'meeting'),
        status = m['status'] ?? 'uploading',
        stage = m['stage'],
        error = m['error'],
        localAudio = m['local_audio'],
        durationSec = m['duration_sec'],
        speakerNames = Map<String, dynamic>.from(m['speaker_names'] ?? {}),
        folderId = m['folder_id'],
        suggestedFolderId = m['suggested_folder_id'],
        favorite = m['favorite'] ?? false,
        recordedAt = DateTime.parse(m['recorded_at']).toLocal(),
        processedAt = m['processed_at'] == null ? null : DateTime.parse(m['processed_at']).toLocal();

  bool get isReady => status == 'ready';
  bool get inProgress => status == 'uploading' || status == 'queued' || status == 'processing';

  String speakerName(int n) => (speakerNames['$n'] as String?)?.trim().isNotEmpty == true
      ? speakerNames['$n'] as String
      : 'Спикер $n';
}

class Segment {
  final int id;
  final int speaker;
  final int startMs;
  final int endMs;
  final String text;

  Segment.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        speaker = m['speaker'],
        startMs = m['start_ms'],
        endMs = m['end_ms'],
        text = m['text'];
}

/// Реплика: подряд идущие фразы одного спикера.
class Turn {
  final int speaker;
  final int startMs;
  final List<String> parts = [];
  Turn(this.speaker, this.startMs);
  String get text => parts.join(' ');
}

List<Turn> groupTurns(List<Segment> segs) {
  final out = <Turn>[];
  for (final s in segs) {
    if (out.isEmpty || out.last.speaker != s.speaker) out.add(Turn(s.speaker, s.startMs));
    out.last.parts.add(s.text);
  }
  return out;
}

/// Пункт итога с таймкодом: определение, формула, пример, важное, ошибка.
class KeyPoint {
  final String text;
  final String kind;
  final int? tSec;
  KeyPoint.fromMap(Map<String, dynamic> m)
      : text = '${m['text'] ?? ''}',
        kind = '${m['kind'] ?? 'note'}',
        tSec = (m['t_sec'] as num?)?.toInt();
}

/// Событие с датой, найденное в разговоре (контрольная, встреча, дедлайн).
class EventItem {
  final String recordingId;
  final String title;
  final DateTime date;
  final String? time;
  final String kind;
  final int? tSec;
  EventItem.fromMap(Map<String, dynamic> m, this.recordingId)
      : title = '${m['title']}',
        date = DateTime.parse('${m['date']}'.substring(0, 10)),
        time = (m['time'] is String && RegExp(r'^\d{1,2}:\d{2}$').hasMatch(m['time'])) ? m['time'] : null,
        kind = '${m['kind'] ?? 'other'}',
        tSec = (m['t_sec'] as num?)?.toInt();

  DateTime get start {
    if (time == null) return date;
    final p = time!.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(p[0]), int.parse(p[1]));
  }
}

class Summary {
  final String summary;
  final List<String> decisions;
  final List<String> openQuestions;
  final List<Map<String, dynamic>> responsibilities;
  final List<KeyPoint> keyPoints;
  final List<(String, List<String>)> sections;
  final List<Map<String, dynamic>> explanations;
  final List<EventItem> events;

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      List<Map<String, dynamic>>.from((v ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));

  Summary.fromMap(Map<String, dynamic> m)
      : summary = m['summary'] ?? '',
        decisions = List<String>.from((m['decisions'] ?? []).map((e) => '$e')),
        openQuestions = List<String>.from((m['open_questions'] ?? []).map((e) => '$e')),
        responsibilities = _maps(m['responsibilities']),
        keyPoints = _maps(m['key_points']).map(KeyPoint.fromMap).where((k) => k.text.isNotEmpty).toList(),
        sections = _maps(m['sections'])
            .map((e) => ('${e['title'] ?? ''}', List<String>.from((e['items'] ?? []).map((x) => '$x'))))
            .where((e) => e.$2.isNotEmpty)
            .toList(),
        explanations = _maps(m['explanations']),
        events = _maps(m['events']).map((e) {
          try {
            return EventItem.fromMap(e, '${m['recording_id']}');
          } catch (_) {
            return null;
          }
        }).whereType<EventItem>().toList();
}

class TaskItem {
  final String id;
  final String? recordingId;
  final String text;
  final String? assignee;
  final String? dueText;
  final DateTime? dueDate;
  final int? tSec;
  final bool forMe;
  final bool done;
  final DateTime createdAt;

  TaskItem.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        recordingId = m['recording_id'],
        text = m['text'],
        assignee = m['assignee'],
        dueText = m['due_text'],
        dueDate = m['due_date'] == null ? null : DateTime.parse(m['due_date']),
        tSec = (m['t_sec'] as num?)?.toInt(),
        forMe = m['for_me'] ?? false,
        done = m['done'] ?? false,
        createdAt = DateTime.parse(m['created_at']).toLocal();
}

class Folder {
  final String id;
  final String name;
  final String color;
  final String kind;
  Folder.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        name = m['name'],
        color = m['color'] ?? '#8B7CFF',
        kind = m['kind'] ?? 'other';
}

class Profile {
  final String? displayName;
  final List<String> nameAliases;
  final List<String> roles;
  final int? grade;
  final bool onboarded;
  final bool isAdmin;
  final String defaultMode;
  final String plan;
  final DateTime? planExpiresAt;
  final int minutesLimit;
  final int secondsUsed;

  Profile.fromMap(Map<String, dynamic> m)
      : displayName = m['display_name'],
        nameAliases = List<String>.from(m['name_aliases'] ?? const []),
        roles = List<String>.from(m['roles'] ?? const []),
        grade = m['grade'],
        onboarded = m['onboarded'] ?? false,
        isAdmin = m['is_admin'] ?? false,
        defaultMode = m['default_mode'] ?? 'meeting',
        plan = m['plan'] ?? 'free',
        planExpiresAt = m['plan_expires_at'] == null ? null : DateTime.parse(m['plan_expires_at']),
        minutesLimit = m['minutes_limit'] ?? 30,
        secondsUsed = m['seconds_used'] ?? 0;

  bool get isPro => plan == 'pro' && (planExpiresAt == null || planExpiresAt!.isAfter(DateTime.now()));
  /// Лимит в минутах с учётом тарифа (Pro — 50 часов в месяц).
  int get effectiveLimit => isPro ? 3000 : minutesLimit;
  int get minutesUsed => (secondsUsed / 60).ceil();
}

String fmtDuration(int? sec) {
  if (sec == null) return '';
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String fmtMs(int ms) => fmtDuration(ms ~/ 1000);
