import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/attendance.dart';
import 'package:school_management_app/models/teacher_attendance.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 11 (Teacher Attendance): teachers can only view their own
/// attendance history and the CL/LP leaves the office logged for them —
/// marking is done by admin/office (teacher_attendance_admin_screen.dart,
/// teacher_record_detail_screen.dart).
class TeacherAttendanceHistoryScreen extends StatefulWidget {
  const TeacherAttendanceHistoryScreen({super.key});

  @override
  State<TeacherAttendanceHistoryScreen> createState() =>
      _TeacherAttendanceHistoryScreenState();
}

class _TeacherAttendanceHistoryScreenState extends State<TeacherAttendanceHistoryScreen> {
  bool _loading = true;
  List<TeacherAttendance> _history = [];
  List<Map<String, dynamic>> _leaves = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final results = await Future.wait<dynamic>([
        supabase
            .from('teacher_attendance')
            .select()
            .eq('teacher_id', teacherId)
            .order('date', ascending: false)
            .limit(200),
        supabase
            .from('teacher_leaves')
            .select('id, leave_date, leave_type, remarks')
            .eq('teacher_id', teacherId)
            .order('leave_date', ascending: false)
            .limit(200),
      ]);
      setState(() {
        _history = (results[0] as List)
            .map((e) => TeacherAttendance.fromJson(e as Map<String, dynamic>))
            .toList();
        _leaves = List<Map<String, dynamic>>.from(results[1] as List);
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

  Color _statusColor(AttendanceStatus status) {
    switch (status.dbValue) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'half_day':
        return Colors.purple;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildLeavesCard() {
    final now = DateTime.now();
    final monthPrefix = DateFormat('yyyy-MM').format(now);
    final clThisMonth = _leaves
        .where((l) => l['leave_type'] == 'CL' && (l['leave_date'] as String).startsWith(monthPrefix))
        .length;
    final summary = AttendanceSummary();
    for (final l in _leaves) {
      summary.addLeave(l['leave_type'] as String);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Leaves', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'CL used in ${DateFormat('MMMM').format(now)}: $clThisMonth of 1',
              style: TextStyle(color: clThisMonth >= 1 ? Colors.orange : Colors.green),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in kLeaveTypes)
                  Chip(
                    label: Text('${categoryLabel(l)}: ${summary.leaves[l]}'),
                    backgroundColor: categoryColor(l).withValues(alpha: 0.12),
                    labelStyle:
                        TextStyle(color: categoryColor(l), fontWeight: FontWeight.w600, fontSize: 12),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (_leaves.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No leaves logged', style: TextStyle(color: Colors.grey)),
              )
            else
              for (final l in _leaves.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event_busy, color: categoryColor(l['leave_type'] as String)),
                  title: Text(DateFormat('EEE, d MMM yyyy').format(DateTime.parse(l['leave_date'] as String))),
                  subtitle: l['remarks'] == null ? null : Text(l['remarks'] as String),
                  trailing: Text(l['leave_type'] as String,
                      style: TextStyle(
                          color: categoryColor(l['leave_type'] as String), fontWeight: FontWeight.w600)),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = AttendanceSummary();
    for (final h in _history) {
      summary.addStatus(h.status.dbValue);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${summary.percentLabel} present (${summary.markedDays} recorded days)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLeavesCard(),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No attendance recorded yet')),
                    )
                  else
                    ..._history.map((h) {
                      final subtitleParts = [
                        if (h.checkInTime != null) 'In: ${DateFormat('h:mm a').format(h.checkInTime!)}',
                        if (h.checkOutTime != null) 'Out: ${DateFormat('h:mm a').format(h.checkOutTime!)}',
                      ];
                      return Card(
                        child: ListTile(
                          leading: Icon(Icons.circle, size: 14, color: _statusColor(h.status)),
                          title: Text(DateFormat('EEEE, d MMM yyyy').format(h.date)),
                          subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
                          trailing: Text(
                              h.status.dbValue == 'half_day' ? 'HALF DAY' : h.status.name.toUpperCase(),
                              style: TextStyle(color: _statusColor(h.status), fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
