import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/exam.dart';
import 'package:school_management_app/models/subject.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 9 of the client spec: unlimited exams per teacher, each with
/// per-class/subject max marks and pass marks so Marks Management (module
/// 10) can auto-compute pass/fail and rank against a real definition
/// instead of a free-text exam_type string.
class ExamManagementScreen extends StatefulWidget {
  const ExamManagementScreen({super.key});

  @override
  State<ExamManagementScreen> createState() => _ExamManagementScreenState();
}

class _ExamManagementScreenState extends State<ExamManagementScreen> {
  bool _loading = true;
  List<Exam> _exams = [];
  List<ClassModel> _classes = [];
  List<Subject> _subjects = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        supabase.from('exams').select().order('exam_date', ascending: false),
        supabase.from(SupabaseConfig.classesTable).select().order('grade'),
        supabase.from('subjects').select().order('name'),
      ]);
      setState(() {
        _exams = (results[0] as List).map((e) => Exam.fromJson(e as Map<String, dynamic>)).toList();
        _classes = (results[1] as List)
            .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
            .toList();
        _subjects =
            (results[2] as List).map((e) => Subject.fromJson(e as Map<String, dynamic>)).toList();
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

  Future<void> _createExam() async {
    final nameCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());
    DateTime? examDate;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Exam'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Exam name (e.g. Test 1, Quarterly, Annual)'),
              ),
              TextField(
                controller: yearCtrl,
                decoration: const InputDecoration(labelText: 'Academic year'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exam date'),
                subtitle:
                    Text(examDate != null ? DateFormat('d MMM yyyy').format(examDate!) : 'Not set'),
                onTap: () async {
                  final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (picked != null) setDialogState(() => examDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await supabase.from('exams').insert({
                    'name': nameCtrl.text.trim(),
                    'academic_year': yearCtrl.text.trim(),
                    'exam_date': examDate?.toIso8601String().substring(0, 10),
                    'created_by': supabase.auth.currentUser?.id,
                  });
                  await AuditService.log(
                      module: 'exams', action: 'create', newValue: {'name': nameCtrl.text.trim()});
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExam(Exam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete exam?'),
        content: Text(
            'This removes "${exam.name}" and its subject/marks configuration. Existing entered marks keep their score but lose the link to this exam.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await supabase.from('exams').delete().eq('id', exam.id);
    await AuditService.log(module: 'exams', action: 'delete', oldValue: {'name': exam.name});
    await _load();
  }

  Future<void> _openSubjectConfig(Exam exam) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExamSubjectConfigSheet(
        exam: exam,
        classes: _classes,
        subjects: _subjects,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Management')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _exams.isEmpty
              ? const Center(child: Text('No exams yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _exams.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = _exams[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.fact_check_outlined),
                          title: Text(e.name),
                          subtitle: Text(
                              '${e.academicYear}${e.examDate != null ? ' · ${DateFormat('d MMM yyyy').format(e.examDate!)}' : ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _openSubjectConfig(e),
                                child: const Text('Subjects'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteExam(e),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createExam,
        icon: const Icon(Icons.add),
        label: const Text('Exam'),
      ),
    );
  }
}

class _ExamSubjectConfigSheet extends StatefulWidget {
  const _ExamSubjectConfigSheet({
    required this.exam,
    required this.classes,
    required this.subjects,
  });

  final Exam exam;
  final List<ClassModel> classes;
  final List<Subject> subjects;

  @override
  State<_ExamSubjectConfigSheet> createState() => _ExamSubjectConfigSheetState();
}

class _ExamSubjectConfigSheetState extends State<_ExamSubjectConfigSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _configs = [];
  ClassModel? _selectedClass;
  Subject? _selectedSubject;
  final _maxCtrl = TextEditingController(text: '100');
  final _passCtrl = TextEditingController(text: '35');

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.classes.isNotEmpty ? widget.classes.first : null;
    _selectedSubject = widget.subjects.isNotEmpty ? widget.subjects.first : null;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('exam_subjects')
          .select('*, subjects(name), classes(grade, section)')
          .eq('exam_id', widget.exam.id);
      setState(() => _configs = List<Map<String, dynamic>>.from(data));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_selectedClass == null || _selectedSubject == null) return;
    final maxMarks = double.tryParse(_maxCtrl.text);
    final passMarks = double.tryParse(_passCtrl.text);
    if (maxMarks == null || passMarks == null || passMarks > maxMarks) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter valid max/pass marks')));
      return;
    }
    try {
      await supabase.from('exam_subjects').insert({
        'exam_id': widget.exam.id,
        'class_id': _selectedClass!.id,
        'subject_id': _selectedSubject!.id,
        'max_marks': maxMarks,
        'pass_marks': passMarks,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _remove(String id) async {
    await supabase.from('exam_subjects').delete().eq('id', id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.exam.name} — subjects & marks',
                style:
                    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DropdownButtonFormField<ClassModel>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(labelText: 'Class'),
              items: widget.classes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedClass = v),
            ),
            DropdownButtonFormField<Subject>(
              initialValue: _selectedSubject,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: widget.subjects
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSubject = v),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max marks'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pass marks'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _add, child: const Text('Add')),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_configs.isEmpty)
              const Text('No subjects configured for this exam yet')
            else
              ..._configs.map((c) {
                final subjectName = (c['subjects'] as Map?)?['name'] as String? ?? '—';
                final cls = c['classes'] as Map?;
                final className = cls != null ? 'Grade ${cls['grade']} – ${cls['section']}' : '—';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('$subjectName · $className'),
                  subtitle: Text('Max ${c['max_marks']} / Pass ${c['pass_marks']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _remove(c['id'] as String),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
