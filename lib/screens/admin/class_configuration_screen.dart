import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/models/subject.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/widgets/searchable_picker.dart';
import 'package:school_management_app/utils/error_messages.dart';

class ClassConfigurationScreen extends StatefulWidget {
  const ClassConfigurationScreen({super.key});

  @override
  State<ClassConfigurationScreen> createState() =>
      _ClassConfigurationScreenState();
}

class _ClassConfigurationScreenState extends State<ClassConfigurationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  List<ClassModel> _classes = [];
  List<Subject> _subjects = [];
  List<Profile> _teachers = [];
  List<Profile> _students = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
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
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'student')
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
        _students = (results[3] as List)
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

  String _teacherName(String? id) =>
      _teachers.firstWhere((t) => t.id == id,
              orElse: () => const Profile(
                  id: '', fullName: 'Unassigned', email: '', role: UserRole.teacher))
          .fullName;

  // ── Classes tab ──────────────────────────────────────────────────────────

  Future<void> _openClassDialog({ClassModel? existing}) async {
    final gradeCtrl = TextEditingController(text: existing?.grade ?? '');
    final sectionCtrl = TextEditingController(text: existing?.section ?? '');
    final yearCtrl = TextEditingController(
        text: existing?.academicYear ?? DateTime.now().year.toString());
    String? teacherId = existing?.teacherId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New Class' : 'Edit Class'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: gradeCtrl,
                    decoration: const InputDecoration(labelText: 'Grade (e.g. 8)')),
                TextField(
                    controller: sectionCtrl,
                    decoration: const InputDecoration(labelText: 'Section (e.g. A)')),
                TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(labelText: 'Academic year')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: teacherId,
                  decoration: const InputDecoration(labelText: 'Homeroom teacher'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Unassigned')),
                    ..._teachers.map(
                        (t) => DropdownMenuItem(value: t.id, child: Text(t.fullName))),
                  ],
                  onChanged: (v) => setDialogState(() => teacherId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  final payload = {
                    'grade': gradeCtrl.text.trim(),
                    'section': sectionCtrl.text.trim(),
                    'academic_year': yearCtrl.text.trim(),
                    'teacher_id': teacherId,
                  };
                  if (existing == null) {
                    await supabase.from(SupabaseConfig.classesTable).insert(payload);
                  } else {
                    await supabase
                        .from(SupabaseConfig.classesTable)
                        .update(payload)
                        .eq('id', existing.id);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadAll();
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

  Future<void> _deleteClass(ClassModel c) async {
    try {
      await supabase.from(SupabaseConfig.classesTable).delete().eq('id', c.id);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Widget _buildClassesTab() {
    return Scaffold(
      body: _classes.isEmpty
          ? const Center(child: Text('No classes yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _classes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = _classes[i];
                return Card(
                  child: ListTile(
                    title: Text(c.displayName),
                    subtitle: Text(
                        'Teacher: ${_teacherName(c.teacherId)} · ${c.academicYear ?? ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openClassDialog(existing: c),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteClass(c),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_class',
        onPressed: () => _openClassDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Class'),
      ),
    );
  }

  // ── Subjects tab ─────────────────────────────────────────────────────────

  Future<void> _addSubject() async {
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Subject'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Subject name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await supabase
                    .from('subjects')
                    .insert({'name': nameCtrl.text.trim()});
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _loadAll();
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsTab() {
    return Scaffold(
      body: _subjects.isEmpty
          ? const Center(child: Text('No subjects yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _subjects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = _subjects[i];
                return Card(
                  child: ListTile(
                    title: Text(s.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        await supabase.from('subjects').delete().eq('id', s.id);
                        await _loadAll();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_subject',
        onPressed: _addSubject,
        icon: const Icon(Icons.add),
        label: const Text('Subject'),
      ),
    );
  }

  // ── Assignments tab (class + subject -> teacher) ────────────────────────

  ClassModel? _assignClass;
  List<Map<String, dynamic>> _assignments = [];

  Future<void> _loadAssignments(String classId) async {
    final data = await supabase
        .from('class_subject_teachers')
        .select('*, subjects(name), profiles(full_name)')
        .eq('class_id', classId);
    setState(() => _assignments = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _addAssignment() async {
    if (_assignClass == null) return;
    String? subjectId = _subjects.isNotEmpty ? _subjects.first.id : null;
    String? teacherId = _teachers.isNotEmpty ? _teachers.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Assign Teacher'),
          content: Column(
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
                items: _teachers
                    .map((t) => DropdownMenuItem(value: t.id, child: Text(t.fullName)))
                    .toList(),
                onChanged: (v) => setDialogState(() => teacherId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (subjectId == null || teacherId == null) return;
                try {
                  await supabase.from('class_subject_teachers').insert({
                    'class_id': _assignClass!.id,
                    'subject_id': subjectId,
                    'teacher_id': teacherId,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadAssignments(_assignClass!.id);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsTab() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ClassModel>(
              initialValue: _assignClass,
              decoration: const InputDecoration(labelText: 'Select class'),
              items: _classes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                  .toList(),
              onChanged: (c) {
                setState(() => _assignClass = c);
                if (c != null) _loadAssignments(c.id);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _assignClass == null
                  ? const Center(child: Text('Pick a class to view assignments'))
                  : _assignments.isEmpty
                      ? const Center(child: Text('No subject teachers assigned yet'))
                      : ListView.separated(
                          itemCount: _assignments.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final a = _assignments[i];
                            return Card(
                              child: ListTile(
                                title: Text(
                                    (a['subjects'] as Map?)?['name'] as String? ?? '—'),
                                subtitle: Text(
                                    (a['profiles'] as Map?)?['full_name'] as String? ??
                                        '—'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () async {
                                    await supabase
                                        .from('class_subject_teachers')
                                        .delete()
                                        .eq('id', a['id'] as String);
                                    await _loadAssignments(_assignClass!.id);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _assignClass == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add_assignment',
              onPressed: _addAssignment,
              icon: const Icon(Icons.add),
              label: const Text('Assign'),
            ),
    );
  }

  // ── Roster tab (class -> enrolled students) ─────────────────────────────

  ClassModel? _rosterClass;
  List<Map<String, dynamic>> _roster = [];

  Future<void> _loadRoster(String classId) async {
    final data = await supabase
        .from('class_students')
        .select('*, profiles(full_name)')
        .eq('class_id', classId);
    setState(() => _roster = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _addToRoster() async {
    if (_rosterClass == null) return;
    final enrolledIds = _roster.map((r) => r['student_id'] as String).toSet();
    final available = _students.where((s) => !enrolledIds.contains(s.id)).toList();
    if (available.isEmpty) return;

    // A student belongs to one class at a time, so enrolling someone who is
    // already in another class moves them — show where they are now so the
    // admin can see that before confirming.
    final enrollments = await supabase.from('class_students').select('student_id, classes(grade, section)');
    final currentClassOf = <String, String>{
      for (final e in (enrollments as List).cast<Map<String, dynamic>>())
        if (e['classes'] != null)
          e['student_id'] as String:
              'Grade ${(e['classes'] as Map)['grade']} – ${(e['classes'] as Map)['section']}',
    };
    if (!mounted) return;

    Profile selected = available.first;
    final rollCtrl = TextEditingController();

    Future<void> pickStudent(void Function(void Function()) setDialogState) async {
      final picked = await showDialog<Profile>(
        context: context,
        builder: (_) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SearchablePicker<Profile>(
              items: available,
              labelOf: (s) => s.fullName,
              subtitleOf: (s) => currentClassOf[s.id] == null
                  ? s.email
                  : '${s.email} · currently in ${currentClassOf[s.id]}',
              onSelected: (s) => Navigator.pop(context, s),
            ),
          ),
        ),
      );
      if (picked != null) setDialogState(() => selected = picked);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Enroll Student'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Student'),
                subtitle: Text(currentClassOf[selected.id] == null
                    ? '${selected.fullName} (${available.length} available)'
                    : '${selected.fullName} — will move from ${currentClassOf[selected.id]}'),
                trailing: const Icon(Icons.search),
                onTap: () => pickStudent(setDialogState),
              ),
              TextField(
                controller: rollCtrl,
                decoration: const InputDecoration(labelText: 'Roll number'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await supabase.from('class_students').upsert(
                    {
                      'class_id': _rosterClass!.id,
                      'student_id': selected.id,
                      'roll_number': rollCtrl.text.trim().isEmpty
                          ? null
                          : rollCtrl.text.trim(),
                    },
                    onConflict: 'student_id',
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadRoster(_rosterClass!.id);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Enroll'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportRoster() async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'class_roster_${_rosterClass?.displayName ?? ''}',
        headers: const ['Student', 'Roll Number'],
        rows: _roster
            .map((r) => [
                  (r['profiles'] as Map?)?['full_name'] as String? ?? '—',
                  r['roll_number'] ?? '',
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

  Widget _buildRosterTab() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ClassModel>(
                    initialValue: _rosterClass,
                    decoration: const InputDecoration(labelText: 'Select class'),
                    items: _classes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                        .toList(),
                    onChanged: (c) {
                      setState(() => _rosterClass = c);
                      if (c != null) _loadRoster(c.id);
                    },
                  ),
                ),
                if (_rosterClass != null)
                  IconButton(
                    icon: const Icon(Icons.table_view_outlined),
                    tooltip: 'Export roster as Excel',
                    onPressed: _roster.isEmpty ? null : _exportRoster,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _rosterClass == null
                  ? const Center(child: Text('Pick a class to view its roster'))
                  : _roster.isEmpty
                      ? const Center(child: Text('No students enrolled yet'))
                      : ListView.separated(
                          itemCount: _roster.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final r = _roster[i];
                            return Card(
                              child: ListTile(
                                title: Text(
                                    (r['profiles'] as Map?)?['full_name'] as String? ??
                                        '—'),
                                subtitle:
                                    Text('Roll no: ${r['roll_number'] ?? '—'}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () async {
                                    await supabase
                                        .from('class_students')
                                        .delete()
                                        .eq('id', r['id'] as String);
                                    await _loadRoster(_rosterClass!.id);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _rosterClass == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add_roster',
              onPressed: _addToRoster,
              icon: const Icon(Icons.add),
              label: const Text('Enroll'),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Configuration'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Classes'),
            Tab(text: 'Subjects'),
            Tab(text: 'Assign Teachers'),
            Tab(text: 'Roster'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildClassesTab(),
                _buildSubjectsTab(),
                _buildAssignmentsTab(),
                _buildRosterTab(),
              ],
            ),
    );
  }
}
