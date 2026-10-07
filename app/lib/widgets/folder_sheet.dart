import 'package:flutter/material.dart';

import '../models.dart';
import '../roles.dart';
import '../services/repo.dart';
import '../theme.dart';

/// Переложить запись на полку (или во «Входящие»).
Future<void> showMoveSheet(BuildContext context, Recording r) async {
  final s = context.sm;
  final folders = Repo.folders.value.isEmpty ? await Repo.loadFolders() : Repo.folders.value;
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 16), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Положить на полку', style: display(18, color: s.text)),
          ),
          ListTile(
            leading: Icon(Icons.inbox_rounded, color: s.muted),
            title: const Text('Входящие'),
            trailing: r.folderId == null ? Icon(Icons.check_rounded, color: s.accentText) : null,
            onTap: () async {
              Navigator.pop(ctx);
              await Repo.moveToFolder(r.id, null);
            },
          ),
          for (final f in folders)
            ListTile(
              leading: CircleAvatar(radius: 8, backgroundColor: hexColor(f.color)),
              title: Text(f.name),
              trailing: r.folderId == f.id ? Icon(Icons.check_rounded, color: s.accentText) : null,
              onTap: () async {
                Navigator.pop(ctx);
                await Repo.moveToFolder(r.id, f.id);
              },
            ),
          ListTile(
            leading: Icon(Icons.add_rounded, color: s.accentText),
            title: Text('Новая полка', style: TextStyle(color: s.accentText, fontWeight: FontWeight.w700)),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await askFolderName(context);
              if (name == null) return;
              await Repo.addFolder(name, folderColors[Repo.folders.value.length % folderColors.length]);
              final f = Repo.folders.value.where((x) => x.name == name).lastOrNull;
              if (f != null) await Repo.moveToFolder(r.id, f.id);
            },
          ),
        ]),
      ),
    ),
  );
}

Future<String?> askFolderName(BuildContext context) async {
  final c = TextEditingController();
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Новая полка'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Например: Физика или ООО Ромашка')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Создать'))],
    ),
  );
  return (v == null || v.isEmpty) ? null : v;
}

Folder? folderById(String? id) => id == null ? null : Repo.folders.value.where((f) => f.id == id).firstOrNull;
