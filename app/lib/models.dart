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

class Summary {
  final String summary;
  final List<String> decisions;
  final List<String> openQuestions;
  final List<Map<String, dynamic>> responsibilities;

  Summary.fromMap(Map<String, dynamic> m)
      : summary = m['summary'] ?? '',
        decisions = List<String>.from((m['decisions'] ?? []).map((e) => '$e')),
        openQuestions = List<String>.from((m['open_questions'] ?? []).map((e) => '$e')),
        responsibilities = List<Map<String, dynamic>>.from(
            (m['responsibilities'] ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
}

class TaskItem {
  final String id;
  final String? recordingId;
  final String text;
  final String? assignee;
  final String? dueText;
  final bool done;
  final DateTime createdAt;

  TaskItem.fromMap(Map<String, dynamic> m)
      : id = m['id'],
        recordingId = m['recording_id'],
        text = m['text'],
        assignee = m['assignee'],
        dueText = m['due_text'],
        done = m['done'] ?? false,
        createdAt = DateTime.parse(m['created_at']).toLocal();
}

class Profile {
  final String plan;
  final DateTime? planExpiresAt;
  final int minutesLimit;
  final int secondsUsed;

  Profile.fromMap(Map<String, dynamic> m)
      : plan = m['plan'] ?? 'free',
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
