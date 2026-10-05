import 'package:flutter_test/flutter_test.dart';
import 'package:sammari/models.dart';

void main() {
  test('fmtDuration', () {
    expect(fmtDuration(65), '01:05');
    expect(fmtDuration(3725), '1:02:05');
  });

  test('groupTurns склеивает реплики одного спикера', () {
    final segs = [
      Segment.fromMap({'id': 1, 'speaker': 1, 'start_ms': 0, 'end_ms': 1000, 'text': 'Привет'}),
      Segment.fromMap({'id': 2, 'speaker': 1, 'start_ms': 1000, 'end_ms': 2000, 'text': 'всем'}),
      Segment.fromMap({'id': 3, 'speaker': 2, 'start_ms': 2000, 'end_ms': 3000, 'text': 'Здравствуйте'}),
    ];
    final t = groupTurns(segs);
    expect(t.length, 2);
    expect(t.first.text, 'Привет всем');
  });
}
