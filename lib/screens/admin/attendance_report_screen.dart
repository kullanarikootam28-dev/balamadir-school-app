import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/screens/teacher/attendance_registry_screen.dart' show weekStartOf;
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/fetch_all.dart';

enum _ReportMode { daily, monthly, annual }

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  bool _loadingClasses = true;
  bool _loadingRows = false;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  _ReportMode _mode = _ReportMode.daily;
  DateTime _anchor = DateTime.now();
  List<Map<String, dynamic>> _rows = [];
  // "classId|studentId" -> roll number, from current enrollments.
  Map<String, String> _rollNumbers = {};

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final data =
          await supabase.from(SupabaseConfig.classesTable).select().order('grade');
      setState(() {
        _classes = (data as List)
            .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingClasses = false);
    }
    await _loadRows();
  }

  (DateTime, DateTime) get _range {
    switch (_mode) {
      case _ReportMode.daily:
        final start = DateTime(_anchor.year, _anchor.month, _anchor.day);
        return (start, start.add(const Duration(days: 1)));
      case _ReportMode.monthly:
        final start = DateTime(_anchor.year, _anchor.month, 1);
        final end = DateTime(_anchor.year, _anchor.month + 1, 1);
        return (start, end);
      case _ReportMode.annual:
        return (DateTime(_anchor.year, 1, 1), DateTime(_anchor.year + 1, 1, 1));
    }
  }

  Future<void> _loadRows() async {
    setState(() => _loadingRows = true);
    try {
      final (start, end) = _range;
      final startIso = DateFormat('yyyy-MM-dd').format(start);
      final endIso = DateFormat('yyyy-MM-dd').format(end);
      final classId = _selectedClass?.id;
      final results = await Future.wait<dynamic>([
        fetchAllRows(() {
          final q = supabase
              .from(SupabaseConfig.attendanceTable)
              .select(
                  'id, date, status, class_id, student_id, profiles!attendance_student_id_fkey(full_name)')
              .gte('date', startIso)
              .lt('date', endIso);
          return (classId == null ? q : q.eq('class_id', classId))
              .order('date', ascending: true)
              .order('id');
        }),
        fetchAllRows(() => supabase
            .from('class_students')
            .select('id, class_id, student_id, roll_number')
            .order('id')),
      ]);
      final rollNumbers = <String, String>{
        for (final e in results[1] as List<Map<String, dynamic>>)
          if (e['roll_number'] != null)
            '${e['class_id']}|${e['student_id']}': e['roll_number'] as String,
      };
      setState(() {
        _rows = results[0] as List<Map<String, dynamic>>;
        _rollNumbers = rollNumbers;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingRows = false);
    }
  }

  void _shiftAnchor(int direction) {
    setState(() {
      switch (_mode) {
        case _ReportMode.daily:
          _anchor = _anchor.add(Duration(days: direction));
          break;
        case _ReportMode.monthly:
          _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
          break;
        case _ReportMode.annual:
          _anchor = DateTime(_anchor.year + direction, 1, 1);
          break;
      }
    });
    _loadRows();
  }

  Map<String, int> get _dailyCounts {
    final counts = <String, int>{
      'present': 0,
      'absent': 0,
      'late': 0,
      'excused': 0,
      'half_day': 0,
    };
    for (final r in _rows) {
      final s = r['status'] as String;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// day-of-month -> attendance % for that day (present+late / total marked)
  Map<int, double> get _monthlyPercents {
    final byDay = <int, List<String>>{};
    for (final r in _rows) {
      final date = DateTime.parse(r['date'] as String);
      byDay.putIfAbsent(date.day, () => []).add(r['status'] as String);
    }
    return byDay.map((day, statuses) {
      final present = _weightedPresent(statuses);
      return MapEntry(day, statuses.isEmpty ? 0 : (present / statuses.length) * 100);
    });
  }

  /// month (1-12) -> attendance %
  Map<int, double> get _annualPercents {
    final byMonth = <int, List<String>>{};
    for (final r in _rows) {
      final date = DateTime.parse(r['date'] as String);
      byMonth.putIfAbsent(date.month, () => []).add(r['status'] as String);
    }
    return byMonth.map((month, statuses) {
      final present = _weightedPresent(statuses);
      return MapEntry(month, statuses.isEmpty ? 0 : (present / statuses.length) * 100);
    });
  }

  double _weightedPresent(List<String> statuses) {
    var total = 0.0;
    for (final s in statuses) {
      if (s == 'present' || s == 'late') {
        total += 1;
      } else if (s == 'half_day') {
        total += 0.5;
      }
    }
    return total;
  }

  String get _anchorLabel {
    switch (_mode) {
      case _ReportMode.daily:
        return DateFormat('EEE, d MMM yyyy').format(_anchor);
      case _ReportMode.monthly:
        return DateFormat('MMMM yyyy').format(_anchor);
      case _ReportMode.annual:
        return _anchor.year.toString();
    }
  }

  Future<void> _openUnlockDialog() async {
    ClassModel? unlockClass = _selectedClass ?? (_classes.isNotEmpty ? _classes.first : null);
    DateTime weekOf = weekStartOf(DateTime.now().subtract(const Duration(days: 7)));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Unlock Attendance Week'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ClassModel>(
                initialValue: unlockClass,
                decoration: const InputDecoration(labelText: 'Class'),
                items: _classes
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                    .toList(),
                onChanged: (c) => setDialogState(() => unlockClass = c),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Week starting (Monday)'),
                subtitle: Text(DateFormat('d MMM yyyy').format(weekOf)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: weekOf,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (picked != null) setDialogState(() => weekOf = weekStartOf(picked));
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (unlockClass == null) return;
                try {
                  await supabase.from('attendance_unlocks').upsert({
                    'class_id': unlockClass!.id,
                    'week_start_date': weekOf.toIso8601String().substring(0, 10),
                    'unlocked_by': supabase.auth.currentUser?.id,
                  }, onConflict: 'class_id,week_start_date');
                  await AuditService.log(
                    module: 'attendance',
                    action: 'unlock_week',
                    newValue: {
                      'class': unlockClass!.displayName,
                      'week_start': weekOf.toIso8601String().substring(0, 10),
                    },
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Week unlocked')));
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  String _classLabel(String? classId) {
    final c = _classes.firstWhere((c) => c.id == classId, orElse: () => _classes.first);
    return c.id == classId ? c.displayName : '—';
  }

  String _studentName(Map<String, dynamic> r) =>
      (r['profiles'] as Map?)?['full_name'] as String? ?? '—';

  String _rollNo(Map<String, dynamic> r) => _rollNumbers['${r['class_id']}|${r['student_id']}'] ?? '';

  Future<void> _exportRows() async {
    try {
      // One row per student (within their class) for the summary tab.
      final byStudent = AttendanceSummary.groupBy(_rows, (r) => '${r['class_id']}|${r['student_id']}');
      final sampleRow = <String, Map<String, dynamic>>{
        for (final r in _rows) '${r['class_id']}|${r['student_id']}': r,
      };
      final studentKeys = byStudent.keys.toList()
        ..sort((a, b) {
          final ra = sampleRow[a]!, rb = sampleRow[b]!;
          final byClass = _classLabel(ra['class_id'] as String?).compareTo(_classLabel(rb['class_id'] as String?));
          if (byClass != 0) return byClass;
          return _studentName(ra).compareTo(_studentName(rb));
        });
      final byClass = AttendanceSummary.groupBy(_rows, (r) => r['class_id'] as String);
      final classIds = byClass.keys.toList()
        ..sort((a, b) => _classLabel(a).compareTo(_classLabel(b)));

      await ExcelExportService.exportWorkbook(
        fileBaseName: 'student_attendance_${_anchorLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
        sheets: [
          ExportSheet(
            name: 'Student Summary',
            headers: ['Class', 'Roll No', 'Student', ...AttendanceSummary.exportHeaders()],
            rows: [
              for (final key in studentKeys)
                [
                  _classLabel(sampleRow[key]!['class_id'] as String?),
                  _rollNo(sampleRow[key]!),
                  _studentName(sampleRow[key]!),
                  ...byStudent[key]!.exportCells(),
                ],
            ],
          ),
          ExportSheet(
            name: 'Class Summary',
            headers: ['Class', ...AttendanceSummary.exportHeaders()],
            rows: [
              for (final id in classIds) [_classLabel(id), ...byClass[id]!.exportCells()],
            ],
          ),
          ExportSheet(
            name: 'Daily Log',
            headers: const ['Date', 'Class', 'Roll No', 'Student', 'Status'],
            rows: [
              for (final r in _rows)
                [
                  r['date'],
                  _classLabel(r['class_id'] as String?),
                  _rollNo(r),
                  _studentName(r),
                  categoryLabel(r['status'] as String),
                ],
            ],
          ),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Attendance Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Export as Excel',
            onPressed: _rows.isEmpty ? null : _exportRows,
          ),
          IconButton(
            icon: const Icon(Icons.lock_open_outlined),
            tooltip: 'Unlock a past week',
            onPressed: _openUnlockDialog,
          ),
        ],
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<ClassModel?>(
                        initialValue: _selectedClass,
                        decoration: const InputDecoration(labelText: 'Class'),
                        items: [
                          const DropdownMenuItem<ClassModel?>(
                              value: null, child: Text('All classes')),
                          ..._classes.map((c) =>
                              DropdownMenuItem(value: c, child: Text(c.displayName))),
                        ],
                        onChanged: (c) {
                          setState(() => _selectedClass = c);
                          _loadRows();
                        },
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<_ReportMode>(
                        segments: const [
                          ButtonSegment(value: _ReportMode.daily, label: Text('Daily')),
                          ButtonSegment(value: _ReportMode.monthly, label: Text('Monthly')),
                          ButtonSegment(value: _ReportMode.annual, label: Text('Annual')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) {
                          setState(() => _mode = s.first);
                          _loadRows();
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: () => _shiftAnchor(-1)),
                          Text(_anchorLabel,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: () => _shiftAnchor(1)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadingRows
                      ? const Center(child: CircularProgressIndicator())
                      : _rows.isEmpty
                          ? const Center(child: Text('No attendance records for this range'))
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child: _mode == _ReportMode.daily
                                  ? _buildDailyChart()
                                  : _mode == _ReportMode.monthly
                                      ? _buildLineChart(_monthlyPercents, isMonthly: true)
                                      : _buildLineChart(_annualPercents, isMonthly: false),
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildDailyChart() {
    final counts = _dailyCounts;
    final labels = ['Present', 'Absent', 'Late', 'Excused', 'Half Day'];
    final keys = ['present', 'absent', 'late', 'excused', 'half_day'];
    final colors = [Colors.green, Colors.red, Colors.orange, Colors.blueGrey, Colors.purple];
    final maxY = (counts.values.isEmpty ? 1 : counts.values.reduce((a, b) => a > b ? a : b))
        .toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY + 1,
        barGroups: [
          for (var i = 0; i < keys.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                  toY: (counts[keys[i]] ?? 0).toDouble(), color: colors[i], width: 28),
            ]),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(labels[value.toInt() % labels.length],
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildLineChart(Map<int, double> percents, {required bool isMonthly}) {
    final keys = percents.keys.toList()..sort();
    final spots = keys.map((k) => FlSpot(k.toDouble(), percents[k]!)).toList();
    final theme = Theme.of(context);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: isMonthly ? 5 : 1,
              getTitlesWidget: (value, meta) {
                final label = isMonthly
                    ? value.toInt().toString()
                    : DateFormat.MMM().format(DateTime(2000, value.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: theme.colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
                show: true, color: theme.colorScheme.primary.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }
}
