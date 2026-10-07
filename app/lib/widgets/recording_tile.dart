import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../modes.dart';
import '../theme.dart';

class RecordingTile extends StatelessWidget {
  final Recording r;
  final VoidCallback onTap;
  final EdgeInsets margin;
  const RecordingTile({super.key, required this.r, required this.onTap, this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5)});

  String get _statusText => switch (r.status) {
        'uploading' => 'Загрузка…',
        'queued' => 'В очереди',
        'processing' => switch (r.stage) {
            'diarizing' => 'Определяю спикеров…',
            'summarizing' => 'Собираю итог…',
            _ => 'Расшифровка…',
          },
        'error' => 'Ошибка обработки',
        'limit_exceeded' => 'Закончились минуты',
        _ => fmtDuration(r.durationSec),
      };

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final m = modeById(r.mode);
    final date = DateFormat('d MMM, HH:mm', 'ru').format(r.recordedAt);
    return Padding(
      padding: margin,
      child: Material(
        color: s.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: s.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: m.color.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                child: Icon(m.icon, color: m.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
                  const SizedBox(height: 3),
                  Text('${m.label} · $date · $_statusText', style: TextStyle(color: s.muted, fontSize: 13)),
                ]),
              ),
              if (r.inProgress)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (r.favorite)
                const Icon(Icons.favorite_rounded, color: AppColors.record, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
