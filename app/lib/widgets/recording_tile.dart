import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../modes.dart';
import '../services/uploader.dart';
import '../theme.dart';
import 'folder_sheet.dart';

class RecordingTile extends StatelessWidget {
  final Recording r;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets margin;
  const RecordingTile({super.key, required this.r, required this.onTap, this.onLongPress, this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5)});

  String get _statusText => switch (r.status) {
        'uploading' => _uploadText(),
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

  String _uploadText() {
    final u = Uploader.state.value[r.id];
    if (u?.error != null) return 'не загрузилось';
    if (u == null || u.progress == 0) return 'загрузка…';
    return 'загрузка ${(u.progress * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) => r.status == 'uploading'
      ? ValueListenableBuilder<Map<String, UploadState>>(valueListenable: Uploader.state, builder: (c, _, __) => _build(c))
      : _build(context);

  Widget _build(BuildContext context) {
    final s = context.sm;
    final m = modeById(r.mode);
    final date = DateFormat('d MMM, HH:mm', 'ru').format(r.recordedAt);
    final folder = folderById(r.folderId);
    return Padding(
      padding: margin,
      child: Material(
        color: s.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: s.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          onLongPress: onLongPress,
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
                  Text('${folder?.name ?? m.label} · $date · $_statusText',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.muted, fontSize: 13)),
                ]),
              ),
              if (r.status == 'uploading')
                ValueListenableBuilder<Map<String, UploadState>>(
                  valueListenable: Uploader.state,
                  builder: (_, st, __) {
                    final u = st[r.id];
                    if (u?.error != null) {
                      return IconButton(
                        tooltip: 'Повторить загрузку',
                        onPressed: r.localAudio == null ? null : () => Uploader.start(r.id, r.localAudio!),
                        icon: Icon(Icons.refresh_rounded, color: s.danger),
                      );
                    }
                    return SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5, value: u == null || u.progress == 0 ? null : u.progress),
                    );
                  },
                )
              else if (r.inProgress)
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
