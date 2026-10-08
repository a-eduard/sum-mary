import 'package:flutter/material.dart';

/// Роль пользователя: готовый набор полок, режим по умолчанию и типы записей,
/// которые выносятся быстрыми кнопками на «Сегодня».
class Role {
  final String id;
  final String label;
  final String hint;
  final IconData icon;
  final String mode;
  final List<String> folders;
  final List<String> modes;
  const Role(this.id, this.label, this.hint, this.icon, this.mode, this.folders, this.modes);
}

const roles = [
  Role('school', 'Школьник', 'Уроки, ДЗ, контрольные', Icons.backpack_rounded, 'lesson', [], ['lesson', 'tutor']),
  Role('student', 'Студент', 'Лекции, семинары, сессия', Icons.school_rounded, 'lecture', [], ['lecture', 'seminar']),
  Role('work', 'Работа и встречи', 'Планёрки, созвоны, Zoom', Icons.groups_rounded, 'meeting',
      ['Планёрки', 'Проекты', 'Созвоны'], ['meeting', 'call']),
  Role('hr', 'HR / рекрутер', 'Собеседования, 1-на-1', Icons.badge_rounded, 'interview',
      ['Вакансии', 'Кандидаты', 'Команда'], ['interview', 'meeting', 'call']),
  Role('sales', 'Продажи', 'Клиенты, переговоры', Icons.handshake_rounded, 'sales', ['Клиенты', 'Сделки'], ['sales', 'call', 'meeting']),
  Role('lead', 'Руководитель', 'Команда, решения, задачи', Icons.workspace_premium_rounded, 'meeting',
      ['Планёрки', '1-на-1', 'Стратегия'], ['meeting', 'call']),
  Role('tutor', 'Репетитор / учитель', 'Занятия с учениками', Icons.co_present_rounded, 'tutor', ['Ученики'], ['tutor', 'call']),
  Role('other', 'Другое', 'Опишу сам', Icons.auto_awesome_rounded, 'meeting', ['Встречи', 'Заметки'], ['meeting', 'call', 'lecture']),
];

Role roleById(String id) => roles.firstWhere((r) => r.id == id, orElse: () => roles.last);

/// Быстрые кнопки на «Сегодня»: типы записей из ролей пользователя (не больше 4).
List<String> quickModes(List<String> roleIds) {
  final out = <String>[];
  for (final r in roleIds) {
    for (final m in roleById(r).modes) {
      if (!out.contains(m)) out.add(m);
    }
  }
  if (out.isEmpty) return const ['meeting', 'lecture', 'lesson', 'call'];
  return out.take(4).toList();
}

/// Подходит ли полка к типу записи: уроку — предметы, собеседованию — вакансии и т. д.
/// Полки без пары (kind пустой) подходят ко всему.
bool folderFitsMode(String? kind, String mode) {
  if (kind == null || kind.isEmpty) return true;
  switch (mode) {
    case 'lesson':
    case 'lecture':
    case 'seminar':
      return kind == 'subject';
    case 'tutor':
      return kind == 'tutor' || kind == 'subject';
    case 'interview':
      return kind == 'hr';
    case 'sales':
      return kind == 'sales';
    default: // встреча, звонок
      return kind != 'subject';
  }
}

/// Какой kind получит новая полка, созданная при записи такого типа.
String folderKindForMode(String mode, List<String> roleIds) => switch (mode) {
      'lesson' || 'lecture' || 'seminar' => 'subject',
      'tutor' => 'tutor',
      'interview' => 'hr',
      'sales' => 'sales',
      _ => roleIds.firstWhere((r) => r != 'school' && r != 'student', orElse: () => 'other'),
    };

/// Предметы по классу (ФГОС, упрощённо).
List<String> schoolSubjects(int grade) {
  if (grade <= 4) return ['Русский язык', 'Литературное чтение', 'Математика', 'Окружающий мир', 'Английский язык'];
  if (grade <= 6) {
    return ['Русский язык', 'Литература', 'Математика', 'История', 'Биология', 'География', 'Английский язык'];
  }
  return [
    'Русский язык', 'Литература', 'Алгебра', 'Геометрия', 'Физика', if (grade >= 8) 'Химия', 'Биология',
    'История', 'Обществознание', 'География', 'Информатика', 'Английский язык',
    if (grade >= 7) 'Вероятность и статистика',
  ];
}

const studentSubjectIdeas = [
  'Математический анализ', 'Линейная алгебра', 'Программирование', 'История России', 'Философия',
  'Экономика', 'Английский язык', 'Физика', 'Право', 'Психология',
];

/// Цвета полок — различимы и в светлой, и в тёмной теме.
const folderColors = [
  '#4F8BFF', '#E07B2E', '#2FA36B', '#8B7CFF', '#D6487A', '#3FB8AF', '#C79A1E', '#6A7BFF', '#E0533D', '#7A8CA3',
];

Color hexColor(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
