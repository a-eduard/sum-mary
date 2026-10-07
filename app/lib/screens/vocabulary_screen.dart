import 'package:flutter/material.dart';

import '../services/repo.dart';
import '../theme.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});
  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  List<Map<String, dynamic>> _terms = [];
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final t = await Repo.vocabulary();
    if (mounted) setState(() => _terms = t);
  }

  Future<void> _add() async {
    if (_c.text.trim().isEmpty) return;
    await Repo.addTerm(_c.text);
    _c.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Словарь терминов')),
      body: Column(children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text('Добавьте имена коллег, названия компаний, продуктов и терминов. '
              'Мари учтёт их при подготовке резюме и исправит в расшифровке.',
              style: TextStyle(color: context.sm.muted)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: TextField(controller: _c, onSubmitted: (_) => _add(),
                decoration: const InputDecoration(hintText: 'Например: DocuSeal'))),
            IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final t in _terms)
              ListTile(
                title: Text(t['term']),
                trailing: IconButton(icon: const Icon(Icons.close),
                    onPressed: () async {
                      await Repo.deleteTerm(t['id']);
                      await _reload();
                    }),
              ),
          ]),
        ),
      ]),
    );
  }
}
