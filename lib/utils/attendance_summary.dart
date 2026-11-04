import 'package:flutter/material.dart';

/// Attendance status categories in display order, plus the two teacher
/// leave types (tracked separately in `teacher_leaves`, not as statuses).
const List<String> kSummaryStatuses = ['present', 'absent', 'late', 'half_day', 'excused'];
const List<String> kLeaveTypes = ['CL', 'LP'];

String categoryLabel(String key) {
  switch (key) {
    case 'present':
      return 'Present';
    case 'absent':
      return 'Absent';
    case 'late':
      return 'Late';
    case 'half_day':
      return 'Half day';
    case 'excused':
      return 'Excused';
    case 'CL':
      return 'Casual leave (CL)';
    case 'LP':
      return 'Loss of pay (LP)';
    default:
      return key;
  }
}

Color categoryColor(String key) {
  switch (key) {
    case 'present':
      return Colors.green;
    case 'absent':
      return Colors.red;
    case 'late':
      return Colors.orange;
    case 'half_day':
      return Colors.purple;
    case 'excused':
      return Colors.blueGrey;
    case 'CL':
      return Colors.teal;
    case 'LP':
      return Colors.brown;
    default:
      return Colors.grey;
  }
}

/// Counts attendance rows by category and computes the attendance % the
/// same way everywhere in the app: present and late count as a full day,
/// half-day as half, everything else as absent.
class AttendanceSummary {
  final Map<String, int> counts = {for (final s in kSummaryStatuses) s: 0};
  final Map<String, int> leaves = {for (final l in kLeaveTypes) l: 0};

  void addStatus(String status) => counts[status] = (counts[status] ?? 0) + 1;
  void addLeave(String type) => leaves[type] = (leaves[type] ?? 0) + 1;

  int get markedDays => counts.values.fold(0, (a, b) => a + b);

  double get attendedDays =>
      (counts['present'] ?? 0) + (counts['late'] ?? 0) + 0.5 * (counts['half_day'] ?? 0);

  /// Null when nothing has been marked, so callers can show "—" instead of
  /// a misleading 0%.
  double? get percent => markedDays == 0 ? null : attendedDays / markedDays * 100;

  String get percentLabel => percent == null ? '—' : '${percent!.toStringAsFixed(1)}%';

  /// Row cells in [kSummaryStatuses] order, then leaves (if [withLeaves]),
  /// then marked days and %, for spreadsheet export.
  List<Object?> exportCells({bool withLeaves = false}) => [
        for (final s in kSummaryStatuses) counts[s] ?? 0,
        if (withLeaves) for (final l in kLeaveTypes) leaves[l] ?? 0,
        markedDays,
        percent == null ? null : double.parse(percent!.toStringAsFixed(1)),
      ];

  static List<String> exportHeaders({bool withLeaves = false}) => [
        for (final s in kSummaryStatuses) categoryLabel(s),
        if (withLeaves) ...kLeaveTypes,
        'Days marked',
        'Attendance %',
      ];

  /// Groups rows by [keyOf] into one summary each.
  static Map<String, AttendanceSummary> groupBy(
    Iterable<Map<String, dynamic>> rows,
    String Function(Map<String, dynamic>) keyOf,
  ) {
    final out = <String, AttendanceSummary>{};
    for (final r in rows) {
      out.putIfAbsent(keyOf(r), AttendanceSummary.new).addStatus(r['status'] as String);
    }
    return out;
  }
}
