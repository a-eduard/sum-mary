import 'package:flutter/material.dart';

/// Роль пользователя: готовый набор полок и режим записи по умолчанию.
class Role {
  final String id;
  final String label;
  final String hint;
  final IconData icon;
  final String mode;
  final List<String> folders;
  const Role(this.id, this.label, this.hint, this.icon, this.mode, this.folders);
}

const roles = [
  Role('school', 'Школьник', 'Уроки, ДЗ, контрольные', Icons.backpack_rounded, 'lesson', []),
  Role('student', 'Студент', 'Лекции, семинары, сессия', Icons.school_rounded, 'lecture', []),
  Role('work', 'Работа и встречи', 'Планёрки, созвоны, Zoom', Icons.groups_rounded, 'meeting', ['Планёрки', 'Проекты', 'Созвоны']),
  Role('hr', 'HR / рекрутер', 'Собеседования, 1-на-1', Icons.badge_rounded, 'interview', ['Вакансии', 'Кандидаты', 'Команда']),
  Role('sales', 'Продажи', 'Клиенты, переговоры', Icons.handshake_rounded, 'sales', ['Клиенты', 'Сделки']),
  Role('lead', 'Руководитель', 'Команда, решения, задачи', Icons.workspace_premium_rounded, 'meeting', ['Планёрки', '1-на-1', 'Стратегия']),
  Role('tutor', 'Репетитор / учитель', 'Занятия с учениками', Icons.co_present_rounded, 'tutor', ['Ученики']),
  Role('other', 'Другое', 'Опишу сам', Icons.auto_awesome_rounded, 'meeting', ['Встречи', 'Заметки']),
];

Role roleById(String id) => roles.firstWhere((r) => r.id == id, orElse: () => roles.last);

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
