import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/models/subject.dart';
import 'package:school_management_app/models/timetable_slot.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/widgets/timetable_grid.dart';
import 'package:school_management_app/utils/error_messages.dart';

class TimetableSetupScreen extends StatefulWidget {
  const TimetableSetupScreen({super.key});

  @override
  State<TimetableSetupScreen> createState() => _TimetableSetupScreenState();
}

class _TimetableSetupScreenState extends State<TimetableSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<ClassModel> _classes = [];
  List<Subject> _subjects = [];
  List<Profile> _teachers = [];
  ClassModel? _selectedClass;
  List<TimetableSlot> _slots = [];
  Set<String> _assignedTeacherIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitial();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        supabase.from(SupabaseConfig.classesTable).select().order('grade'),
        supabase.from('subjects').select().order('name'),
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'teacher')
            .order('full_name'),
      ]);
      setState(() {
        _classes = (results[0] as List)
            .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _subjects = (results[1] as List)
            .map((e) => Subject.fromJson(e as Map<String, dynamic>))
            .toList();
        _teachers = (results[2] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList();
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

  Future<void> _loadSlots(String classId) async {
    final results = await Future.wait([
      supabase
          .from('timetable_slots')
          .select('*, subjects(name), profiles(full_name)')
          .eq('class_id', classId),
      supabase.from('class_subject_teachers').select('teacher_id').eq('class_id', classId),
    ]);
    final homeroomTeacherId =
        _classes.firstWhere((c) => c.id == classId, orElse: () => _classes.first).teacherId;
    setState(() {
      _slots = (results[0] as List)
          .map((e) => TimetableSlot.fromJson(e as Map<String, dynamic>))
          .toList();
      _assignedTeacherIds = {
        if (homeroomTeacherId != null) homeroomTeacherId,
        ...(results[1] as List)
            .cast<Map<String, dynamic>>()
            .map((r) => r['teacher_id'] as String),
      };
    });
  }

  /// Teachers actually tied to the currently selected class (homeroom or a
  /// subject assignment) sorted first, so the dropdown reflects real
  /// timetable-relevant staff instead of every teacher in the school.
  List<Profile> get _orderedTeachersForSelectedClass {
    final assigned = <Profile>[];
    final rest = <Profile>[];
    for (final t in _teachers) {
      (_assignedTeacherIds.contains(t.id) ? assigned : rest).add(t);
    }
    return [...assigned, ...rest];
  }

  Future<void> _editCell(int day, int period, TimetableSlot? existing) async {
    if (_selectedClass == null) return;

    String? subjectId = existing?.subjectId ?? (_subjects.isNotEmpty ? _subjects.first.id : null);
    String? teacherId = existing?.teacherId ?? (_teachers.isNotEmpty ? _teachers.first.id : null);
    TimeOfDay startTime = existing?.startTime != null
        ? _parseTime(existing!.startTime!)
        : const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = existing?.endTime != null
        ? _parseTime(existing!.endTime!)
        : const TimeOfDay(hour: 9, minute: 45);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('${kWeekdayNames[day - 1]} · Period $period'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: subjectId,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: _subjects
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => subjectId = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: teacherId,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                  items: _orderedTeachersForSelectedClass
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(_assignedTeacherIds.contains(t.id)
                                ? '★ ${t.fullName}'
                                : t.fullName),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => teacherId = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start time'),
                  trailing: Text(startTime.format(context)),
                  onTap: () async {
                    final picked =
                        await showTimePicker(context: dialogContext, initialTime: startTime);
                    if (picked != null) setDialogState(() => startTime = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End time'),
                  trailing: Text(endTime.format(context)),
                  onTap: () async {
                    final picked =
                        await showTimePicker(context: dialogContext, initialTime: endTime);
                    if (picked != null) setDialogState(() => endTime = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  await supabase.from('timetable_slots').delete().eq('id', existing.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadSlots(_selectedClass!.id);
                },
                child: const Text('Delete'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  final payload = {
                    'class_id': _selectedClass!.id,
                    'day_of_week': day,
                    'period_number': period,
                    'subject_id': subjectId,
                    'teacher_id': teacherId,
                    'start_time': _formatTime(startTime),
                    'end_time': _formatTime(endTime),
                  };
                  if (existing == null) {
                    await supabase.from('timetable_slots').insert(payload);
                  } else {
                    await supabase
                        .from('timetable_slots')
                        .update(payload)
                        .eq('id', existing.id);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadSlots(_selectedClass!.id);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String hhmmss) {
    final parts = hhmmss.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Widget _buildByClassTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<ClassModel>(
            initialValue: _selectedClass,
            decoration: const InputDecoration(labelText: 'Select class'),
            items: _classes
                .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                .toList(),
            onChanged: (c) {
              setState(() => _selectedClass = c);
              if (c != null) _loadSlots(c.id);
            },
          ),
          const SizedBox(height: 16),
          if (_selectedClass == null)
            const Expanded(
              child: Center(child: Text('Pick a class to edit its timetable')),
            )
          else
            Expanded(
              child: TimetableGrid(
                slots: _slots,
                onCellTap: (day, period, existing) => _editCell(day, period, existing),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timetable Setup'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'By Class'), Tab(text: 'Bulk Assign')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildByClassTab(),
                _BulkAssignTab(
                  classes: _classes,
                  subjects: _subjects,
                  teachers: _teachers,
                  onApplied: () {
                    if (_selectedClass != null) _loadSlots(_selectedClass!.id);
                  },
                ),
              ],
            ),
    );
  }
}

/// Module 1 of the enhancement pass: assign one subject/teacher/time slot to
/// several classes at once, with a conflict check so the same teacher can't
/// be bulk-booked into two classrooms during the same period.
class _BulkAssignTab extends StatefulWidget {
  const _BulkAssignTab({
    required this.classes,
    required this.subjects,
    required this.teachers,
    required this.onApplied,
  });

  final List<ClassModel> classes;
  final List<Subject> subjects;
  final List<Profile> teachers;
  final VoidCallback onApplied;

  @override
  State<_BulkAssignTab> createState() => _BulkAssignTabState();
}

class _BulkAssignTabState extends State<_BulkAssignTab> {
  int _day = 1;
  int _period = 1;
  String? _subjectId;
  String? _teacherId;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 9, minute: 45);
  final Set<String> _selectedClassIds = {};
  bool _applying = false;
  Map<String, Set<String>> _classSubjectTeacherIds = {};

  @override
  void initState() {
    super.initState();
    _loadClassTeacherAssignments();
  }

  Future<void> _loadClassTeacherAssignments() async {
    final data =
        await supabase.from('class_subject_teachers').select('class_id, teacher_id');
    final map = <String, Set<String>>{};
    for (final row in (data as List).cast<Map<String, dynamic>>()) {
      map.putIfAbsent(row['class_id'] as String, () => {}).add(row['teacher_id'] as String);
    }
    if (mounted) setState(() => _classSubjectTeacherIds = map);
  }

  /// Teachers already tied to any of the currently-checked classes (homeroom
  /// or a subject assignment) — shown first in the Teacher dropdown so a
  /// real assignment doesn't get lost in a flat list of every teacher.
  Set<String> get _recommendedTeacherIds {
    final ids = <String>{};
    for (final classId in _selectedClassIds) {
      ids.addAll(_classSubjectTeacherIds[classId] ?? {});
      final homeroom =
          widget.classes.firstWhere((c) => c.id == classId, orElse: () => widget.classes.first).teacherId;
      if (homeroom != null) ids.add(homeroom);
    }
    return ids;
  }

  List<Profile> get _orderedTeachers {
    final recommended = _recommendedTeacherIds;
    final first = <Profile>[];
    final rest = <Profile>[];
    for (final t in widget.teachers) {
      (recommended.contains(t.id) ? first : rest).add(t);
    }
    return [...first, ...rest];
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _apply() async {
    if (_selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select at least one class')));
      return;
    }
    if (_teacherId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a teacher')));
      return;
    }

    setState(() => _applying = true);
    try {
      // Conflict check: is this teacher already booked at this day/period
      // for a class OUTSIDE the selected set?
      final existing = await supabase
          .from('timetable_slots')
          .select('class_id, classes(grade, section)')
          .eq('teacher_id', _teacherId!)
          .eq('day_of_week', _day)
          .eq('period_number', _period);

      final conflicts = (existing as List)
          .cast<Map<String, dynamic>>()
          .where((row) => !_selectedClassIds.contains(row['class_id'] as String))
          .toList();

      if (conflicts.isNotEmpty) {
        final teacherName =
            widget.teachers.firstWhere((t) => t.id == _teacherId).fullName;
        final busyWith = conflicts.map((row) {
          final c = row['classes'] as Map?;
          return c != null ? 'Grade ${c['grade']} – ${c['section']}' : 'another class';
        }).join(', ');
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Scheduling conflict'),
              content: Text(
                  '$teacherName is already teaching $busyWith at ${kWeekdayNames[_day - 1]} · Period $_period. '
                  'Remove that class from your selection or pick a different teacher/time.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK')),
              ],
            ),
          );
        }
        return;
      }

      final rows = _selectedClassIds
          .map((classId) => {
                'class_id': classId,
                'day_of_week': _day,
                'period_number': _period,
                'subject_id': _subjectId,
                'teacher_id': _teacherId,
                'start_time': _formatTime(_startTime),
                'end_time': _formatTime(_endTime),
              })
          .toList();

      await supabase
          .from('timetable_slots')
          .upsert(rows, onConflict: 'class_id,day_of_week,period_number');

      await AuditService.log(
        module: 'timetable',
        action: 'bulk_assign',
        newValue: {
          'class_count': _selectedClassIds.length,
          'day': kWeekdayNames[_day - 1],
          'period': _period,
        },
      );

      widget.onApplied();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Applied to ${_selectedClassIds.length} class(es)')));
        setState(() => _selectedClassIds.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _day,
                decoration: const InputDecoration(labelText: 'Day'),
                items: [
                  for (var d = 1; d <= 6; d++)
                    DropdownMenuItem(value: d, child: Text(kWeekdayNames[d - 1])),
                ],
                onChanged: (v) => setState(() => _day = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _period,
                decoration: const InputDecoration(labelText: 'Period'),
                items: [
                  for (var p = 1; p <= 8; p++)
                    DropdownMenuItem(value: p, child: Text('Period $p')),
                ],
                onChanged: (v) => setState(() => _period = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _subjectId,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: widget.subjects
              .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
              .toList(),
          onChanged: (v) => setState(() => _subjectId = v),
        ),
        DropdownButtonFormField<String>(
          initialValue: _teacherId,
          decoration: const InputDecoration(labelText: 'Teacher'),
          items: _orderedTeachers
              .map((t) => DropdownMenuItem(
                    value: t.id,
                    child: Text(_recommendedTeacherIds.contains(t.id)
                        ? '★ ${t.fullName}'
                        : t.fullName),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _teacherId = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start time'),
                subtitle: Text(_startTime.format(context)),
                onTap: () async {
                  final picked =
                      await showTimePicker(context: context, initialTime: _startTime);
                  if (picked != null) setState(() => _startTime = picked);
                },
              ),
            ),
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End time'),
                subtitle: Text(_endTime.format(context)),
                onTap: () async {
                  final picked =
                      await showTimePicker(context: context, initialTime: _endTime);
                  if (picked != null) setState(() => _endTime = picked);
                },
              ),
            ),
          ],
        ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Apply to classes',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () => setState(() {
                if (_selectedClassIds.length == widget.classes.length) {
                  _selectedClassIds.clear();
                } else {
                  _selectedClassIds
                    ..clear()
                    ..addAll(widget.classes.map((c) => c.id));
                }
              }),
              child: Text(_selectedClassIds.length == widget.classes.length
                  ? 'Deselect all'
                  : 'Select all'),
            ),
          ],
        ),
        if (_selectedClassIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Chip(label: Text('${_selectedClassIds.length} class(es) selected')),
          ),
        ...widget.classes.map((c) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(c.displayName),
              value: _selectedClassIds.contains(c.id),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selectedClassIds.add(c.id);
                } else {
                  _selectedClassIds.remove(c.id);
                }
              }),
            )),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _applying ? null : _apply,
          child: _applying
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Apply to ${_selectedClassIds.length} class(es)'),
        ),
      ],
    );
  }
}
