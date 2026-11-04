import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

const List<String> kAttendanceStatuses = ['present', 'absent', 'late', 'excused', 'half_day'];

String statusLabel(String status) => status == 'half_day' ? 'HALF DAY' : status.toUpperCase();

/// Monday of the calendar week containing [d] (module 11: weekly lock).
DateTime weekStartOf(DateTime d) {
  final normalized = DateTime(d.year, d.month, d.day);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

class AttendanceRegistryScreen extends StatefulWidget {
  const AttendanceRegistryScreen({super.key});

  @override
  State<AttendanceRegistryScreen> createState() =>
      _AttendanceRegistryScreenState();
}

class _AttendanceRegistryScreenState extends State<AttendanceRegistryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  DateTime _selectedDate = DateTime.now();

  List<Map<String, dynamic>> _roster = []; // {student_id, full_name}
  final Map<String, String> _statusByStudent = {}; // student_id -> status
  bool _saving = false;
  bool _weekLocked = false;

  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMyClasses();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyClasses() async {
    setState(() => _loading = true);
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final assigned = await supabase
          .from('class_subject_teachers')
          .select('classes(*)')
          .eq('teacher_id', teacherId);
      final homeroom = await supabase
          .from(SupabaseConfig.classesTable)
          .select()
          .eq('teacher_id', teacherId);

      final seen = <String>{};
      final classes = <ClassModel>[];
      for (final row in (assigned as List)) {
        final c = (row as Map<String, dynamic>)['classes'];
        if (c != null && seen.add((c as Map<String, dynamic>)['id'] as String)) {
          classes.add(ClassModel.fromJson(c));
        }
      }
      for (final row in (homeroom as List)) {
        final c = row as Map<String, dynamic>;
        if (seen.add(c['id'] as String)) classes.add(ClassModel.fromJson(c));
      }

      setState(() => _classes = classes);
      if (classes.isNotEmpty) {
        _selectedClass = classes.first;
        await _loadRosterAndAttendance();
        await _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRosterAndAttendance() async {
    if (_selectedClass == null) return;
    final roster = await supabase
        .from('class_students')
        .select('student_id, roll_number, profiles(full_name)')
        .eq('class_id', _selectedClass!.id);

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final existing = await supabase
        .from(SupabaseConfig.attendanceTable)
        .select('student_id, status')
        .eq('class_id', _selectedClass!.id)
        .eq('date', dateStr);

    final existingMap = {
      for (final e in (existing as List))
        (e as Map<String, dynamic>)['student_id'] as String: e['status'] as String,
    };

    setState(() {
      _roster = List<Map<String, dynamic>>.from(roster);
      _statusByStudent
        ..clear()
        ..addAll({
          for (final r in _roster)
            r['student_id'] as String:
                existingMap[r['student_id'] as String] ?? 'present',
        });
    });

    await _checkWeekLock();
  }

  /// Module 11: attendance auto-locks after the calendar week it belongs to
  /// ends, unless office staff has explicitly unlocked that class+week.
  Future<void> _checkWeekLock() async {
    if (_selectedClass == null) return;
    final selectedWeekStart = weekStartOf(_selectedDate);
    final currentWeekStart = weekStartOf(DateTime.now());
    if (!selectedWeekStart.isBefore(currentWeekStart)) {
      setState(() => _weekLocked = false);
      return;
    }
    try {
      final unlock = await supabase
          .from('attendance_unlocks')
          .select('id')
          .eq('class_id', _selectedClass!.id)
          .eq('week_start_date', DateFormat('yyyy-MM-dd').format(selectedWeekStart))
          .maybeSingle();
      setState(() => _weekLocked = unlock == null);
    } catch (_) {
      setState(() => _weekLocked = true);
    }
  }

  Future<void> _loadHistory() async {
    if (_selectedClass == null) return;
    final data = await supabase
        .from(SupabaseConfig.attendanceTable)
        .select('*, profiles!attendance_student_id_fkey(full_name)')
        .eq('class_id', _selectedClass!.id)
        .order('date', ascending: false)
        .limit(100);
    setState(() => _history = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadRosterAndAttendance();
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedClass == null) return;
    if (_weekLocked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This week is locked. Ask office staff to unlock it first.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final teacherId = supabase.auth.currentUser!.id;
      final rows = _roster.map((r) {
        final studentId = r['student_id'] as String;
        return {
          'student_id': studentId,
          'class_id': _selectedClass!.id,
          'date': dateStr,
          'status': _statusByStudent[studentId] ?? 'present',
          'marked_by_teacher_id': teacherId,
        };
      }).toList();

      await supabase
          .from(SupabaseConfig.attendanceTable)
          .upsert(rows, onConflict: 'student_id,class_id,date');

      await AuditService.log(
        module: 'attendance',
        action: 'mark',
        newValue: {'class_id': _selectedClass!.id, 'date': dateStr, 'count': rows.length},
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Attendance saved')));
      }
      await _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
    if (_classes.isEmpty) {
      return const Center(child: Text('You are not assigned to any class yet'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ClassModel>(
                  initialValue: _selectedClass,
                  decoration: const InputDecoration(labelText: 'Class'),
                  items: _classes
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c.displayName)))
                      .toList(),
                  onChanged: (c) {
                    setState(() => _selectedClass = c);
                    _loadRosterAndAttendance();
                    _loadHistory();
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(DateFormat.yMMMd().format(_selectedDate)),
              ),
            ],
          ),
        ),
        if (_weekLocked)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This week is locked — ask office staff to unlock it before editing.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _weekLocked
                    ? null
                    : () => setState(() {
                          for (final r in _roster) {
                            _statusByStudent[r['student_id'] as String] = 'present';
                          }
                        }),
                icon: const Icon(Icons.done_all),
                label: const Text('Mark all present'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _roster.isEmpty
              ? const Center(child: Text('No students enrolled in this class'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _roster.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = _roster[i];
                    final studentId = r['student_id'] as String;
                    final name =
                        (r['profiles'] as Map?)?['full_name'] as String? ?? '—';
                    final status = _statusByStudent[studentId] ?? 'present';
                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle: Text('Roll no: ${r['roll_number'] ?? '—'}'),
                        trailing: DropdownButton<String>(
                          value: status,
                          items: kAttendanceStatuses
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      statusLabel(s),
                                      style: TextStyle(color: _statusColor(s)),
                                    ),
                                  ))
                              .toList(),
                          onChanged: _weekLocked
                              ? null
                              : (v) => setState(() => _statusByStudent[studentId] = v!),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving || _roster.isEmpty || _weekLocked ? null : _saveAttendance,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Attendance'),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return const Center(child: Text('No attendance history yet'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = _history[i];
        final status = h['status'] as String;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _statusColor(status).withValues(alpha: 0.15),
              child: Icon(Icons.circle, color: _statusColor(status), size: 14),
            ),
            title: Text((h['profiles'] as Map?)?['full_name'] as String? ?? '—'),
            subtitle: Text(h['date'] as String),
            trailing: Text(status.toUpperCase(),
                style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.w600)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Registry'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Mark Attendance'), Tab(text: 'History')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildMarkTab(), _buildHistoryTab()],
            ),
    );
  }
}
