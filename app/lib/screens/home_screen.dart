import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/local_files.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/recording_tile.dart';
import 'record_screen.dart';
import 'recording_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _recordingsKey = GlobalKey<_RecordingsPageState>();

  Widget _item(int i, IconData icon, String label, {VoidCallback? onTap}) {
    final sel = _tab == i && onTap == null;
    final color = sel ? AppColors.accent : AppColors.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap ?? () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [RecordingsPage(key: _recordingsKey), const TasksScreen(), const SettingsScreen()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: SizedBox(
        width: 68,
        height: 68,
        child: FloatingActionButton(
          backgroundColor: AppColors.record,
          shape: const CircleBorder(),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordScreen())),
          child: const Icon(Icons.mic, size: 32, color: Colors.white),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: AppColors.card,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(children: [
          _item(0, Icons.graphic_eq, 'Записи'),
          _item(1, Icons.check_circle_outline, 'Задачи'),
          const SizedBox(width: 76),
          _item(-1, Icons.upload_file, 'Импорт', onTap: () {
            setState(() => _tab = 0);
            _recordingsKey.currentState?.importMenu();
          }),
          _item(2, Icons.settings_outlined, 'Настройки'),
        ]),
      ),
    );
  }
}

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});
  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  final _q = TextEditingController();
  List<Recording>? _found;
  String _filter = 'all';
  late final Stream<List<Recording>> _stream = Repo.recordings();

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _found = null);
      return;
    }
    final r = await Repo.search(q.trim());
    if (mounted) setState(() => _found = r);
  }

  /// Импорт аудиофайлов: записи звонков, диктофон, файлы из мессенджеров.
  Future<void> _import({bool call = false}) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (res == null) return;
    for (final f in res.files.where((f) => f.path != null)) {
      final copy = await LocalFiles.importCopy(f.path!);
      final id = await Repo.createRecording(source: call ? 'call' : 'import', localPath: copy.path);
      Repo.uploadAndQueue(id, File(copy.path)).catchError((_) {});
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено файлов: ${res.files.length}. Мари уже обрабатывает их.')));
    }
  }

  void importMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.phone_in_talk),
            title: const Text('Запись телефонного звонка'),
            subtitle: const Text('Включите запись звонков в «Телефоне», затем выберите файл. '
                'Обычно папка: Music/Recordings/Call Recordings'),
            onTap: () {
              Navigator.pop(context);
              _import(call: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.audio_file),
            title: const Text('Аудиофайл'),
            subtitle: const Text('Диктофон, голосовые, записи лекций'),
            onTap: () {
              Navigator.pop(context);
              _import();
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          const Text('СамМари', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(onPressed: importMenu, icon: const Icon(Icons.upload_file), tooltip: 'Импорт'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextField(
          controller: _q,
          onChanged: _search,
          decoration: const InputDecoration(hintText: 'Поиск по записям', prefixIcon: Icon(Icons.search), isDense: true),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          for (final (k, label) in [('all', 'Все'), ('mic', 'Встречи'), ('call', 'Звонки'), ('import', 'Импорт'), ('fav', 'Избранное')])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
            ),
        ]),
      ),
      Expanded(
        child: StreamBuilder<List<Recording>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Нет связи с сервером\n${snap.error}', textAlign: TextAlign.center));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            var list = _found ?? snap.data!;
            list = switch (_filter) {
              'fav' => list.where((r) => r.favorite).toList(),
              'all' => list,
              'mic' => list.where((r) => r.source == 'mic' || r.source == 'desktop').toList(),
              _ => list.where((r) => r.source == _filter).toList(),
            };
            if (list.isEmpty) return const _Empty();
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: list.length,
              itemBuilder: (_, i) => RecordingTile(
                r: list[i],
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => RecordingScreen(recordingId: list[i].id))),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.graphic_eq, size: 64, color: AppColors.accent),
            SizedBox(height: 16),
            Text('Записей пока нет', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Нажмите на кнопку микрофона — Мари запишет встречу,\nрасшифрует её и выделит задачи',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
}
