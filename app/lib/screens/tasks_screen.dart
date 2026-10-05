import 'package:flutter/material.dart';

import '../models.dart';
import '../services/repo.dart';
import '../theme.dart';
import 'recording_screen.dart';

/// Все задачи из всех записей.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _showDone = false;
  late final Stream<List<TaskItem>> _stream = Repo.tasks();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text('Задачи', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Открытые')), ButtonSegment(value: true, label: Text('Выполненные'))],
          selected: {_showDone},
          onSelectionChanged: (s) => setState(() => _showDone = s.first),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<TaskItem>>(
          stream: _stream,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!.where((t) => t.done == _showDone).toList();
            if (list.isEmpty) {
              return const Center(child: Text('Задачи из ваших записей появятся здесь', style: TextStyle(color: AppColors.muted)));
            }
            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final t = list[i];
                return Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline)),
                  onDismissed: (_) => Repo.deleteTask(t.id),
                  child: Card(
                    child: CheckboxListTile(
                      value: t.done,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => Repo.setTaskDone(t.id, v ?? false),
                      title: Text(t.text),
                      subtitle: Text([if (t.assignee != null) t.assignee!, if (t.dueText != null) 'срок: ${t.dueText}'].join(' · '),
                          style: const TextStyle(color: AppColors.muted)),
                      secondary: t.recordingId == null ? null : IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: t.recordingId!))),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
