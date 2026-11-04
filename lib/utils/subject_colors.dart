import 'package:flutter/material.dart';

/// Assigns each subject a consistent accent color (by name), reused across
/// the timetable, gradebook, and report card screens so a subject is always
/// recognizable by the same color.
const List<Color> _kSubjectPalette = [
  Color(0xFFE0A82E), // amber
  Color(0xFF3DDC84), // green
  Color(0xFF4A90D9), // blue
  Color(0xFFE5484D), // red
  Color(0xFF9B6BD9), // purple
  Color(0xFF2FB8C6), // teal
  Color(0xFFE07A5F), // terracotta
  Color(0xFF6BAF6B), // sage
];

Color subjectColor(String subjectName) {
  final hash = subjectName.codeUnits.fold<int>(0, (a, b) => a + b);
  return _kSubjectPalette[hash % _kSubjectPalette.length];
}
