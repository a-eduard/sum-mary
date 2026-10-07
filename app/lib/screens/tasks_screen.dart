import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/repo.dart';
import '../theme.dart';
import 'recording_screen.dart';

/// Все задачи из всех записей: мои / все / выполненные.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _tab = 'mine';
  late final Stream<List<TaskItem>> _stream = Repo.tasks();

  Future<void> _add() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая задача'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Что сделать')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Добавить'))],
      ),
    );
    if (v != null && v.isNotEmpty) await Repo.addTask(v, forMe: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
        child: Row(children: [
          Expanded(child: Text('Задачи', style: display(24, color: s.text))),
          IconButton(onPressed: _add, tooltip: 'Добавить задачу', icon: Icon(Icons.add_rounded, color: s.text)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'mine', label: Text('Мои')),
            ButtonSegment(value: 'all', label: Text('Все')),
            ButtonSegment(value: 'done', label: Text('Готово')),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() => _tab = v.first),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<TaskItem>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Нет связи с сервером', style: TextStyle(color: s.muted)));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var list = switch (_tab) {
              'mine' => snap.data!.where((t) => !t.done && t.forMe).toList(),
              'all' => snap.data!.where((t) => !t.done).toList(),
              _ => snap.data!.where((t) => t.done).toList(),
            };
            list.sort((a, b) => (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100)));
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    switch (_tab) {
                      'mine' => 'Здесь появятся задачи, которые поручили вам или вы пообещали сделать',
                      'all' => 'Задачи из ваших записей появятся здесь',
                      _ => 'Выполненных задач пока нет',
                    },
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.muted, height: 1.4),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 140),
              itemCount: list.length,
              itemBuilder: (_, i) => _TaskCard(task: list[i]),
            );
          },
        ),
      ),
    ]);
  }
}

class _TaskCard extends StatelessWidget {
  final TaskItem task;
  const _TaskCard({required this.task});

  String? _due() {
    if (task.dueDate == null) return task.dueText;
    final now = DateTime.now();
    final d = task.dueDate!.difference(DateTime(now.year, now.month, now.day)).inDays;
    return switch (d) {
      < 0 => 'просрочено · ${DateFormat('d MMM', 'ru').format(task.dueDate!)}',
      0 => 'сегодня',
      1 => 'завтра',
      _ => DateFormat('E, d MMM', 'ru').format(task.dueDate!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final due = _due();
    final overdue = task.dueDate != null && !task.done && task.dueDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    return Dismissible(
      key: ValueKey(task.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(color: s.success.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
        child: Icon(task.done ? Icons.undo_rounded : Icons.check_rounded, color: s.success),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: s.danger.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.delete_outline_rounded, color: s.danger),
      ),
      onDismissed: (d) => d == DismissDirection.startToEnd ? Repo.setTaskDone(task.id, !task.done) : Repo.deleteTask(task.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: s.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: task.recordingId == null
              ? null
              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: task.recordingId!))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(
                tooltip: task.done ? 'Вернуть' : 'Выполнено',
                onPressed: () => Repo.setTaskDone(task.id, !task.done),
                icon: Icon(task.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: task.done ? s.success : s.teal, size: 26),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(task.text,
                        style: TextStyle(
                            color: task.done ? s.muted : s.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.3,
                            decoration: task.done ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (task.forMe) _Chip('Вам', s.accentText),
                      if (task.assignee != null && !task.forMe) _Chip(task.assignee!, s.muted),
                      if (due != null) _Chip(due, overdue ? s.danger : s.heroText),
                    ]),
                  ]),
                ),
              ),
              if (task.recordingId != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Icon(Icons.chevron_right_rounded, color: s.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
