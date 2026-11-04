import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';

/// A date range with an inclusive [start] and exclusive [end], plus a
/// human label for file names and headings.
class ReportRange {
  const ReportRange(this.start, this.end, this.label);

  final DateTime start;
  final DateTime end;
  final String label;

  String get startIso => DateFormat('yyyy-MM-dd').format(start);
  String get endIso => DateFormat('yyyy-MM-dd').format(end);

  /// Safe for file names.
  String get slug => label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static ReportRange thisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return ReportRange(start, DateTime(now.year, now.month + 1, 1), DateFormat('MMMM yyyy').format(start));
  }
}

/// Asks which period a report/export should cover: this month, the last 3
/// months, the current academic year (from `academic_years.is_current`), or
/// a custom range. Returns null if cancelled.
Future<ReportRange?> showExportRangeDialog(BuildContext context, {String title = 'Choose period'}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  ReportRange? academicYear;
  try {
    final row = await supabase
        .from('academic_years')
        .select('year_label, start_date, end_date')
        .eq('is_current', true)
        .maybeSingle();
    if (row != null && row['start_date'] != null) {
      final start = DateTime.parse(row['start_date'] as String);
      final end = row['end_date'] != null
          ? DateTime.parse(row['end_date'] as String).add(const Duration(days: 1))
          : tomorrow;
      academicYear = ReportRange(start, end, 'Academic year ${row['year_label']}');
    }
  } catch (_) {
    // Optional choice — just omit it if the lookup fails.
  }
  if (!context.mounted) return null;

  return showDialog<ReportRange>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(title),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, ReportRange.thisMonth()),
          child: const ListTile(leading: Icon(Icons.today), title: Text('This month')),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(
            dialogContext,
            ReportRange(DateTime(now.year, now.month - 2, 1), tomorrow, 'Last 3 months'),
          ),
          child: const ListTile(leading: Icon(Icons.date_range), title: Text('Last 3 months')),
        ),
        if (academicYear != null)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, academicYear),
            child: ListTile(leading: const Icon(Icons.school), title: Text(academicYear.label)),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: dialogContext,
              firstDate: DateTime(2020),
              lastDate: today,
              initialDateRange: DateTimeRange(start: DateTime(now.year, now.month, 1), end: today),
            );
            if (picked == null || !dialogContext.mounted) return;
            final fmt = DateFormat('d MMM yyyy');
            Navigator.pop(
              dialogContext,
              ReportRange(
                picked.start,
                picked.end.add(const Duration(days: 1)),
                '${fmt.format(picked.start)} to ${fmt.format(picked.end)}',
              ),
            );
          },
          child: const ListTile(leading: Icon(Icons.edit_calendar), title: Text('Custom range…')),
        ),
      ],
    ),
  );
}
