import 'package:flutter/material.dart';

import '../roles.dart';
import '../services/repo.dart';
import '../theme.dart';
import '../widgets/mari_orb.dart';

/// Первый вход: «Кто вы?» → готовые полки под роль (можно убрать/добавить свои).
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  final bool fromSettings;
  const OnboardingScreen({super.key, required this.onDone, this.fromSettings = false});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _roles = <String>[];
  int _grade = 9;
  final _picked = <String, Set<String>>{}; // роль → выбранные полки
  final _extra = <String, List<String>>{}; // роль → свои полки
  final _input = <String, TextEditingController>{};
  bool _saving = false;

  List<String> _options(String role) => switch (role) {
        'school' => schoolSubjects(_grade),
        'student' => studentSubjectIdeas,
        _ => roleById(role).folders,
      };

  void _initPicks() {
    for (final r in _roles) {
      _picked.putIfAbsent(r, () => r == 'student' ? <String>{} : _options(r).toSet());
      _extra.putIfAbsent(r, () => []);
      _input.putIfAbsent(r, () => TextEditingController());
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final existing = (await Repo.loadFolders()).map((f) => f.name.toLowerCase()).toSet();
      final items = <(String, String, String)>[];
      var ci = existing.length;
      for (final r in _roles) {
        for (final name in [..._options(r).where((o) => _picked[r]!.contains(o)), ..._extra[r]!]) {
          if (existing.add(name.toLowerCase())) {
            items.add((name, folderColors[ci++ % folderColors.length], r == 'school' || r == 'student' ? 'subject' : r));
          }
        }
      }
      await Repo.createFolders(items);
      await Repo.saveOnboarding(
          roles: _roles, grade: _roles.contains('school') ? _grade : null, defaultMode: roleById(_roles.first).mode);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Scaffold(
      appBar: widget.fromSettings ? AppBar(title: const Text('Роль и полки')) : null,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _step == 0 ? _rolesStep(s) : _foldersStep(s),
        ),
      ),
    );
  }

  Widget _rolesStep(Sm s) => Column(key: const ValueKey(0), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 16), children: [
            const Center(child: MariOrb(size: 96)),
            const SizedBox(height: 20),
            Text('Привет! Я Мари', textAlign: TextAlign.center, style: display(24, color: s.text)),
            const SizedBox(height: 8),
            Text('Расскажите, что будете записывать — я подготовлю полки и итоги под вас. Можно выбрать несколько.',
                textAlign: TextAlign.center, style: TextStyle(color: s.muted, height: 1.4)),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.12,
              children: [
                for (final r in roles)
                  _RoleCard(
                    role: r,
                    selected: _roles.contains(r.id),
                    onTap: () => setState(() => _roles.contains(r.id) ? _roles.remove(r.id) : _roles.add(r.id)),
                  ),
              ],
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FilledButton(
            onPressed: _roles.isEmpty
                ? null
                : () => setState(() {
                      _initPicks();
                      _step = 1;
                    }),
            child: const Text('Дальше'),
          ),
        ),
      ]);

  Widget _foldersStep(Sm s) => Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), children: [
            Row(children: [
              IconButton(onPressed: () => setState(() => _step = 0), icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Назад'),
              const SizedBox(width: 4),
              Expanded(child: Text('Ваши полки', style: display(22, color: s.text))),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text('Записи можно раскладывать по полкам — или просто записывать, а Мари подскажет, куда положить.',
                  style: TextStyle(color: s.muted, height: 1.4)),
            ),
            for (final r in _roles) _roleBlock(s, roleById(r)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FilledButton(
            onPressed: _saving ? null : _finish,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Готово'),
          ),
        ),
      ]);

  Widget _roleBlock(Sm s, Role r) {
    final opts = _options(r.id);
    final picked = _picked[r.id]!;
    void addOwn() {
      final v = _input[r.id]!.text.trim();
      if (v.isEmpty) return;
      setState(() {
        _extra[r.id]!.add(v);
        _input[r.id]!.clear();
      });
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r.icon, color: s.accentText),
          const SizedBox(width: 8),
          Text(r.label, style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        if (r.id == 'school') ...[
          const SizedBox(height: 12),
          Text('Класс', style: TextStyle(color: s.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var g = 1; g <= 11; g++)
              ChoiceChip(
                label: Text('$g'),
                selected: _grade == g,
                showCheckmark: false,
                labelStyle: TextStyle(color: _grade == g ? s.onAccent : s.text, fontWeight: FontWeight.w700),
                onSelected: (_) => setState(() {
                  _grade = g;
                  _picked['school'] = schoolSubjects(g).toSet();
                }),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        if (r.id == 'student')
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Выберите предметы или добавьте свои', style: TextStyle(color: s.muted, fontSize: 13)),
          ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in opts)
            FilterChip(
              label: Text(o),
              selected: picked.contains(o),
              labelStyle: TextStyle(color: picked.contains(o) ? s.onAccent : s.text, fontWeight: FontWeight.w600),
              onSelected: (v) => setState(() => v ? picked.add(o) : picked.remove(o)),
            ),
          for (final o in _extra[r.id]!)
            InputChip(label: Text(o), onDeleted: () => setState(() => _extra[r.id]!.remove(o))),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _input[r.id],
          onSubmitted: (_) => addOwn(),
          decoration: InputDecoration(
            isDense: true,
            hintText: switch (r.id) {
              'tutor' => 'Имя ученика',
              'school' || 'student' => 'Свой предмет или преподаватель',
              _ => 'Своя полка',
            },
            suffixIcon: IconButton(onPressed: addOwn, icon: const Icon(Icons.add_rounded), tooltip: 'Добавить'),
          ),
        ),
      ]),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final Role role;
  final bool selected;
  final VoidCallback onTap;
  const _RoleCard({required this.role, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = context.sm;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? s.accent.withValues(alpha: context.isDark ? .22 : .12) : s.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), side: BorderSide(color: selected ? s.accent : s.border, width: selected ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(role.icon, color: selected ? s.accentText : s.muted, size: 26),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(role.label, style: TextStyle(color: s.text, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(role.hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
