import 'package:flutter/material.dart';

/// Режим записи: определяет, какой итог соберёт Мари.
class RecMode {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  const RecMode(this.id, this.label, this.icon, this.color);
}

const recModes = [
  RecMode('lesson', 'Урок', Icons.menu_book_rounded, Color(0xFF4F8BFF)),
  RecMode('lecture', 'Лекция', Icons.school_rounded, Color(0xFF8B7CFF)),
  RecMode('seminar', 'Семинар', Icons.forum_rounded, Color(0xFF3FB8AF)),
  RecMode('meeting', 'Встреча', Icons.groups_rounded, Color(0xFF2FA36B)),
  RecMode('call', 'Звонок', Icons.call_rounded, Color(0xFFE07B2E)),
  RecMode('interview', 'Собеседование', Icons.badge_rounded, Color(0xFFD6487A)),
  RecMode('sales', 'Продажи', Icons.handshake_rounded, Color(0xFFC79A1E)),
  RecMode('tutor', 'Репетитор', Icons.person_rounded, Color(0xFF6A7BFF)),
];

RecMode modeById(String? id) => recModes.firstWhere((m) => m.id == id, orElse: () => recModes[3]);
