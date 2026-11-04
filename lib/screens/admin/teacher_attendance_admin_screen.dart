import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/screens/teacher/attendance_registry_screen.dart'
    show kAttendanceStatuses, statusLabel;
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/services/teacher_records_export.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/widgets/export_range_dialog.dart';

enum _ReportMode { day, summary }

/// Module 11 (Teacher Attendance) of the client spec: office/admin marks
/// it, teachers can only view their own history
/// (teacher_attendance_history_screen.dart). Two tabs: marking (as before)
/// and a report tab the client specifically asked for, with a day view
/// (today's roll call) and a range summary (category counts + % per
/// teacher, exportable as the same workbook as Teacher Records).
class TeacherAttendanceAdminScreen extends StatefulWidget {
  const TeacherAttendanceAdminScreen({super.key, this.initialTab = 0});

  /// 0 = Mark Attendance, 1 = Reports — lets the admin dashboard's "Teacher
  /// Attendance Reports" card open straight on the Reports tab.
  final int initialTab;

  @override
  State<TeacherAttendanceAdminScreen> createState() =>
      _TeacherAttendanceAdminScreenState();
}

class _TeacherAttendanceAdminScreenState extends State<TeacherAttendanceAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  bool _saving = false;
  List<Profile> _teachers = [];
  DateTime _selectedDate = DateTime.now();
  final Map<String, String> _statusByTeacher = {};

  bool _reportLoading = true;
  DateTime _reportDate = DateTime.now();
  List<Map<String, dynamic>> _reportRows = [];

  _ReportMode _reportMode = _ReportMode.day;
  ReportRange _summaryRange = ReportRange.thisMonth();
  TeacherRecordsData? _summaryData;
  bool _summaryLoading = false;
  bool _summaryExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _load();
    _loadReport();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'teacher')
            .order('full_name'),
        supabase
            .from('teacher_attendance')
            .select('teacher_id, status')
            .eq('date', DateFormat('yyyy-MM-dd').format(_selectedDate)),
      ]);
      final teachers =
          (results[0] as List).map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
      final existing = {
        for (final e in results[1] as List)
          (e as Map<String, dynamic>)['teacher_id'] as String: e['status'] as String,
      };
      setState(() {
        _teachers = teachers;
        _statusByTeacher
          ..clear()
          ..addAll({for (final t in teachers) t.id: existing[t.id] ?? 'present'});
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadReport() async {
    setState(() => _reportLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_reportDate);
      final data = await supabase
          .from('teacher_attendance')
          .select(
              'status, check_in_time, check_out_time, remarks, profiles!teacher_attendance_teacher_id_fkey(full_name)')
          .eq('date', dateStr)
          .order('profiles(full_name)');
      setState(() => _reportRows = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _load();
    }
  }

  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _reportDate = picked);
      await _loadReport();
    }
  }

  Future<void> _loadSummary() async {
    setState(() => _summaryLoading = true);
    try {
      final data = await TeacherRecordsData.load(range: _summaryRange);
      if (mounted) setState(() => _summaryData = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _pickSummaryRange() async {
    final range = await showExportRangeDialog(context, title: 'Summary for');
    if (range == null || !mounted) return;
    setState(() => _summaryRange = range);
    await _loadSummary();
  }

  Future<void> _setReportMode(_ReportMode mode) async {
    setState(() => _reportMode = mode);
    if (mode == _ReportMode.summary && _summaryData == null && !_summaryLoading) {
      await _loadSummary();
    }
  }

  Future<void> _exportSummary() async {
    final data = _summaryData;
    if (data == null) return;
    setState(() => _summaryExporting = true);
    try {
      await data.export('teacher_attendance');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _summaryExporting = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final adminId = supabase.auth.currentUser?.id;
      await supabase.from('teacher_attendance').upsert([
        for (final t in _teachers)
          {
            'teacher_id': t.id,
            'date': dateStr,
            'status': _statusByTeacher[t.id] ?? 'present',
            'marked_by': adminId,
          },
      ], onConflict: 'teacher_id,date');
      await AuditService.log(
          module: 'teacher_attendance', action: 'mark', newValue: {'date': dateStr});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Teacher attendance saved')));
      }
      if (DateFormat('yyyy-MM-dd').format(_reportDate) == dateStr) {
        await _loadReport();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportReport() async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'teacher_attendance_${DateFormat('yyyy-MM-dd').format(_reportDate)}',
        headers: const ['Teacher', 'Status', 'Check In', 'Check Out', 'Remarks'],
        rows: _reportRows
            .map((r) => [
                  (r['profiles'] as Map?)?['full_name'] ?? '—',
                  statusLabel(r['status'] as String),
                  r['check_in_time'] != null
                      ? DateFormat('h:mm a').format(DateTime.parse(r['check_in_time'] as String).toLocal())
                      : '',
                  r['check_out_time'] != null
                      ? DateFormat('h:mm a').format(DateTime.parse(r['check_out_time'] as String).toLocal())
                      : '',
                  r['remarks'] ?? '',
                ])
            .toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'excused':
        return Colors.blueGrey;
      case 'half_day':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _buildMarkTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat.yMMMd().format(_selectedDate)),
          ),
        ),
        Expanded(
          child: _teachers.isEmpty
              ? const Center(child: Text('No teacher accounts yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _teachers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = _teachers[i];
                    final status = _statusByTeacher[t.id] ?? 'present';
                    return Card(
                      child: ListTile(
                        title: Text(t.fullName),
                        trailing: DropdownButton<String>(
                          value: status,
                          items: kAttendanceStatuses
                              .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(statusLabel(s),
                                      style: TextStyle(color: _statusColor(s)))))
                              .toList(),
                          onChanged: (v) => setState(() => _statusByTeacher[t.id] = v!),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving || _teachers.isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Attendance'),
          ),
        ),
      ],
    );
  }

  Widget _buildReportTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<_ReportMode>(
            segments: const [
              ButtonSegment(value: _ReportMode.day, label: Text('Day'), icon: Icon(Icons.today)),
              ButtonSegment(
                  value: _ReportMode.summary, label: Text('Summary'), icon: Icon(Icons.summarize)),
            ],
            selected: {_reportMode},
            onSelectionChanged: (s) => _setReportMode(s.first),
          ),
        ),
        Expanded(
          child: _reportMode == _ReportMode.day ? _buildDayReport() : _buildSummaryReport(),
        ),
      ],
    );
  }

  Widget _buildDayReport() {
    final presentCount = _reportRows
        .where((r) => r['status'] == 'present' || r['status'] == 'late')
        .length;
    final absentCount = _reportRows.where((r) => r['status'] == 'absent').length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickReportDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat.yMMMd().format(_reportDate)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _reportRows.isEmpty ? null : _exportReport,
                icon: const Icon(Icons.table_view_outlined, size: 16),
                label: const Text('Export'),
              ),
            ],
          ),
        ),
        if (!_reportLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.green.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Present: $presentCount',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: Colors.red.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Absent: $absentCount',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _reportLoading
              ? const Center(child: CircularProgressIndicator())
              : _reportRows.isEmpty
                  ? const Center(child: Text('No attendance recorded for this date'))
                  : RefreshIndicator(
                      onRefresh: _loadReport,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _reportRows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = _reportRows[i];
                          final status = r['status'] as String;
                          final name = (r['profiles'] as Map?)?['full_name'] as String? ?? '—';
                          final checkIn = r['check_in_time'] != null
                              ? DateFormat('h:mm a').format(DateTime.parse(r['check_in_time'] as String).toLocal())
                              : null;
                          final checkOut = r['check_out_time'] != null
                              ? DateFormat('h:mm a').format(DateTime.parse(r['check_out_time'] as String).toLocal())
                              : null;
                          final subtitle = [
                            if (checkIn != null) 'In: $checkIn',
                            if (checkOut != null) 'Out: $checkOut',
                          ].join(' · ');
                          return Card(
                            child: ListTile(
                              leading: Icon(Icons.circle, size: 14, color: _statusColor(status)),
                              title: Text(name),
                              subtitle: subtitle.isEmpty ? null : Text(subtitle),
                              trailing: Text(statusLabel(status),
                                  style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w600)),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _categoryChip(String key, int count) => Chip(
        label: Text('${categoryLabel(key)}: $count'),
        backgroundColor: categoryColor(key).withValues(alpha: 0.12),
        labelStyle: TextStyle(color: categoryColor(key), fontWeight: FontWeight.w600, fontSize: 12),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _buildSummaryReport() {
    final data = _summaryData;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickSummaryRange,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_summaryRange.label),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: data == null || _summaryExporting ? null : _exportSummary,
                icon: _summaryExporting
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_view_outlined, size: 16),
                label: const Text('Export'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _summaryLoading || data == null
              ? const Center(child: CircularProgressIndicator())
              : data.teachers.isEmpty
                  ? const Center(child: Text('No teacher accounts yet'))
                  : RefreshIndicator(
                      onRefresh: _loadSummary,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: data.teachers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final t = data.teachers[i];
                          final summary = data.summaries[t['id']]!;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(t['full_name'] as String,
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Text(summary.percentLabel,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: summary.percent == null
                                                  ? Colors.grey
                                                  : summary.percent! >= 75
                                                      ? Colors.green
                                                      : Colors.orange)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final s in kSummaryStatuses)
                                        if (summary.counts[s]! > 0) _categoryChip(s, summary.counts[s]!),
                                      for (final l in kLeaveTypes)
                                        if (summary.leaves[l]! > 0) _categoryChip(l, summary.leaves[l]!),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Attendance'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'Mark Attendance'), Tab(text: 'Reports')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildMarkTab(), _buildReportTab()],
            ),
    );
  }
}
