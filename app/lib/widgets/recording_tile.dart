import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme.dart';

class RecordingTile extends StatelessWidget {
  final Recording r;
  final VoidCallback onTap;
  const RecordingTile({super.key, required this.r, required this.onTap});

  IconData get _icon => switch (r.source) {
        'call' => Icons.phone_in_talk,
        'import' => Icons.upload_file,
        'desktop' => Icons.computer,
        _ => Icons.mic,
      };

  String get _statusText => switch (r.status) {
        'uploading' => 'Загрузка…',
        'queued' => 'В очереди',
        'processing' => switch (r.stage) {
            'diarizing' => 'Определяю спикеров…',
            'summarizing' => 'Готовлю резюме…',
            _ => 'Расшифровка…',
          },
        'error' => 'Ошибка обработки',
        'limit_exceeded' => 'Закончились минуты',
        _ => fmtDuration(r.durationSec),
      };

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM, HH:mm', 'ru').format(r.recordedAt);
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(backgroundColor: AppColors.accent.withValues(alpha: .15), child: Icon(_icon, color: AppColors.accent)),
        title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$date · $_statusText', style: const TextStyle(color: AppColors.muted)),
        trailing: r.inProgress
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : (r.favorite ? const Icon(Icons.favorite, color: AppColors.record, size: 18) : null),
      ),
    );
  }
}
