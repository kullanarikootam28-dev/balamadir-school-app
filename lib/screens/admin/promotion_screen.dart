import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 17 of the client spec: promote all students of a class into a
/// target class at year end, while preserving marks/attendance/fee
/// history. class_students holds a student's *current* class (one row per
/// student, enforced by 022_class_students_unique_student.sql), so promotion
/// moves that row to the target class. History is unaffected: attendance
/// and grades each store their own class_id, and a `promotions` row records
/// every move.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  bool _loading = true;
  bool _promoting = false;
  List<ClassModel> _classes = [];
  ClassModel? _fromClass;
  ClassModel? _toClass;
  List<Map<String, dynamic>> _roster = [];
  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    try {
      final data =
          await supabase.from(SupabaseConfig.classesTable).select().order('grade');
      setState(() {
        _classes =
            (data as List).map((e) => ClassModel.fromJson(e as Map<String, dynamic>)).toList();
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

  Future<void> _loadRoster(String classId) async {
    final data = await supabase
        .from('class_students')
        .select('*, profiles(full_name)')
        .eq('class_id', classId);
    setState(() {
      _roster = List<Map<String, dynamic>>.from(data);
      _selectedStudentIds
        ..clear()
        ..addAll(_roster.map((r) => r['student_id'] as String));
    });
  }

  Future<void> _promote() async {
    if (_fromClass == null || _toClass == null || _selectedStudentIds.isEmpty) return;
    if (_fromClass!.id == _toClass!.id) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Source and target class must differ')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Promote students?'),
        content: Text(
            'This moves ${_selectedStudentIds.length} student(s) from ${_fromClass!.displayName} into ${_toClass!.displayName}. Their marks, attendance, and fee history for ${_fromClass!.displayName} stay untouched. Roll numbers are cleared for the new class.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Promote'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _promoting = true);
    try {
      await supabase.from('class_students').upsert(
        [
          for (final studentId in _selectedStudentIds)
            {'class_id': _toClass!.id, 'student_id': studentId, 'roll_number': null},
        ],
        onConflict: 'student_id',
      );
      await supabase.from('promotions').insert([
        for (final studentId in _selectedStudentIds)
          {
            'student_id': studentId,
            'from_class_id': _fromClass!.id,
            'to_class_id': _toClass!.id,
            'academic_year': _toClass!.academicYear ?? DateTime.now().year.toString(),
            'promoted_by': supabase.auth.currentUser?.id,
          },
      ]);
      await AuditService.log(
        module: 'promotion',
        action: 'promote',
        oldValue: {'from_class': _fromClass!.displayName, 'count': _selectedStudentIds.length},
        newValue: {'to_class': _toClass!.displayName},
      );
      final promotedCount = _selectedStudentIds.length;
      await _loadRoster(_fromClass!.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Promoted $promotedCount student(s)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promote Students')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<ClassModel>(
                    initialValue: _fromClass,
                    decoration: const InputDecoration(labelText: 'From class'),
                    items: _classes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                        .toList(),
                    onChanged: (c) {
                      setState(() => _fromClass = c);
                      if (c != null) _loadRoster(c.id);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ClassModel>(
                    initialValue: _toClass,
                    decoration: const InputDecoration(labelText: 'To class'),
                    items: _classes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                        .toList(),
                    onChanged: (c) => setState(() => _toClass = c),
                  ),
                  const SizedBox(height: 16),
                  if (_fromClass != null)
                    Text('Roster (${_roster.length}) — uncheck to exclude',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: _fromClass == null
                        ? const Center(child: Text('Pick a source class'))
                        : _roster.isEmpty
                            ? const Center(child: Text('No students enrolled in this class'))
                            : ListView.builder(
                                itemCount: _roster.length,
                                itemBuilder: (context, i) {
                                  final r = _roster[i];
                                  final studentId = r['student_id'] as String;
                                  final name =
                                      (r['profiles'] as Map?)?['full_name'] as String? ?? '—';
                                  return CheckboxListTile(
                                    value: _selectedStudentIds.contains(studentId),
                                    title: Text(name),
                                    onChanged: (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedStudentIds.add(studentId);
                                        } else {
                                          _selectedStudentIds.remove(studentId);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                  ),
                  FilledButton(
                    onPressed: _promoting || _fromClass == null || _toClass == null
                        ? null
                        : _promote,
                    child: _promoting
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Promote ${_selectedStudentIds.length} student(s)'),
                  ),
                ],
              ),
            ),
    );
  }
}
