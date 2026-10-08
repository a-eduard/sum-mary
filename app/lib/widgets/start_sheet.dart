import 'package:flutter/material.dart';

import '../models.dart';
import '../modes.dart';
import '../roles.dart';
import '../services/repo.dart';
import '../theme.dart';
import 'folder_sheet.dart';
import 'mari_orb.dart';

/// Перед записью: что записываем (режим) и на какую полку. Запись стартует только по кнопке.
/// [importCall] — вместо записи выбрать файл звонка.
Future<void> showStartSheet(BuildContext context,
    {required String mode, required void Function(String mode, String? folderId) onStart, bool importCall = false}) async {
  if (Repo.folders.value.isEmpty) {
    try {
      await Repo.loadFolders();
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StartSheet(mode: mode, onStart: onStart, importCall: importCall),
  );
}

class _StartSheet extends StatefulWidget {
  final String mode;
  final bool importCall;
  final void Function(String mode, String? folderId) onStart;
  const _StartSheet({required this.mode, required this.onStart, required this.importCall});
  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  late String _mode = widget.mode;
  String? _folder;
  bool _allFolders = false;
  bool _allModes = false;

  List<String> get _roleIds => Repo.me.value?.roles ?? const [];

  String get _question => switch (_mode) {
        'lesson' => 'Какой урок?',
        'lecture' => 'Какая лекция?',
        'seminar' => 'Какой семинар?',
        'tutor' => 'С кем занятие?',
        'interview' => 'На какую вакансию?',
        'sales' => 'Какой клиент?',
        'call' => 'Куда положить звонок?',
        _ => 'Куда положить запись?',
      };

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    final m = modeById(_mode);
    return ValueListenableBuilder<List<Folder>>(
      valueListenable: Repo.folders,
      builder: (context, folders, _) {
        // Уроку — предметы, встрече — рабочие полки. Остальные спрятаны под «Показать все полки».
        final fit = folders.where((f) => folderFitsMode(f.kind, _mode)).toList();
        final rest = folders.where((f) => !folderFitsMode(f.kind, _mode)).toList();
        final shown = _allFolders || fit.isEmpty ? [...fit, ...rest] : fit;
        // Типы записей: сначала типы ролей пользователя, остальные — по «Ещё».
        final mine = quickModes(_roleIds);
        final modes = [
          ...recModes.where((x) => mine.contains(x.id) || x.id == _mode),
          if (_allModes) ...recModes.where((x) => !mine.contains(x.id) && x.id != _mode),
        ];
        Widget tile(String? id, String name, Widget lead) {
          final sel = _folder == id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: sel ? s.accent.withValues(alpha: context.isDark ? .22 : .12) : s.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16), side: BorderSide(color: sel ? s.accent : s.border, width: sel ? 1.5 : 1)),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: lead,
                title: Text(name, style: TextStyle(color: s.text, fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                trailing: sel ? Icon(Icons.check_rounded, color: s.accentText) : null,
                onTap: () => setState(() => _folder = id),
              ),
            ),
          );
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .75,
          maxChildSize: .95,
          minChildSize: .4,
          builder: (context, scroll) => Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: s.border, borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), children: [
                Text(_question, style: display(20, color: s.text)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final x in modes)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          avatar: Icon(x.icon, size: 16, color: _mode == x.id ? s.onAccent : x.color),
                          label: Text(x.label),
                          selected: _mode == x.id,
                          showCheckmark: false,
                          labelStyle: TextStyle(color: _mode == x.id ? s.onAccent : s.text, fontWeight: FontWeight.w600),
                          onSelected: (_) => setState(() {
                            _mode = x.id;
                            if (_folder != null && !folderFitsMode(folderById(_folder)?.kind, _mode)) _folder = null;
                          }),
                        ),
                      ),
                    if (!_allModes && modes.length < recModes.length)
                      ActionChip(
                        avatar: Icon(Icons.more_horiz_rounded, size: 16, color: s.muted),
                        label: const Text('Ещё'),
                        onPressed: () => setState(() => _allModes = true),
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
                for (final f in shown)
                  tile(f.id, f.name, Container(width: 14, height: 14, decoration: BoxDecoration(color: hexColor(f.color), shape: BoxShape.circle))),
                tile(null, 'Без полки — разберу потом', Icon(Icons.inbox_rounded, color: s.muted)),
                if (!_allFolders && fit.isNotEmpty && rest.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _allFolders = true),
                    child: Text('Показать все полки (${folders.length})', style: TextStyle(color: s.muted, fontWeight: FontWeight.w600)),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    final name = await askFolderName(context);
                    if (name == null) return;
                    await Repo.addFolder(name, folderColors[Repo.folders.value.length % folderColors.length],
                        kind: folderKindForMode(_mode, _roleIds));
                    final f = Repo.folders.value.where((x) => x.name == name).lastOrNull;
                    if (f != null && mounted) setState(() => _folder = f.id);
                  },
                  icon: Icon(Icons.add_rounded, color: s.accentText),
                  label: Text('Новая полка', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onStart(_mode, _folder);
                    },
                    icon: widget.importCall
                        ? const Icon(Icons.upload_file_rounded)
                        : const MariOrb(size: 26, glow: false, child: Icon(Icons.mic_rounded, size: 14, color: Color(0xFF0F1015))),
                    label: Text(widget.importCall ? 'Выбрать запись звонка' : 'Начать запись · ${m.label}'),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
