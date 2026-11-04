import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/exam.dart';
import 'package:school_management_app/models/subject.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

class _Assignment {
  _Assignment(this.classModel, this.subject);
  final ClassModel classModel;
  final Subject subject;
  String get label => '${classModel.displayName} · ${subject.name}';
}

class GradebookInputScreen extends StatefulWidget {
  const GradebookInputScreen({super.key});

  @override
  State<GradebookInputScreen> createState() => _GradebookInputScreenState();
}

class _GradebookInputScreenState extends State<GradebookInputScreen> {
  bool _loading = true;
  List<_Assignment> _assignments = [];
  _Assignment? _selected;
  final _examTypeCtrl = TextEditingController(text: 'Midterm');

  List<Exam> _exams = [];
  Exam? _selectedExam;
  Map<String, dynamic>? _examSubjectConfig; // max_marks / pass_marks for selectedExam+selected

  List<Map<String, dynamic>> _roster = [];
  final Map<String, TextEditingController> _scoreCtrls = {};
  final Map<String, TextEditingController> _maxScoreCtrls = {};
  // Report-card remark per student for the selected formal exam
  // (report_card_remarks is keyed on student + exam, not subject).
  final Map<String, TextEditingController> _remarkCtrls = {};
  final Map<String, String> _savedRemarks = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  @override
  void dispose() {
    _examTypeCtrl.dispose();
    for (final c in _scoreCtrls.values) {
      c.dispose();
    }
    for (final c in _maxScoreCtrls.values) {
      c.dispose();
    }
    for (final c in _remarkCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    setState(() => _loading = true);
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('class_subject_teachers')
          .select('classes(*), subjects(*)')
          .eq('teacher_id', teacherId);

      final assignments = <_Assignment>[];
      for (final row in (data as List)) {
        final r = row as Map<String, dynamic>;
        if (r['classes'] != null && r['subjects'] != null) {
          assignments.add(_Assignment(
            ClassModel.fromJson(r['classes'] as Map<String, dynamic>),
            Subject.fromJson(r['subjects'] as Map<String, dynamic>),
          ));
        }
      }

      final examsData = await supabase.from('exams').select().order('exam_date', ascending: false);
      final exams = (examsData as List).map((e) => Exam.fromJson(e as Map<String, dynamic>)).toList();

      setState(() {
        _assignments = assignments;
        _exams = exams;
      });
      if (assignments.isNotEmpty) {
        _selected = assignments.first;
        await _loadRoster();
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

  Future<void> _loadRoster() async {
    if (_selected == null) return;
    final roster = await supabase
        .from('class_students')
        .select('student_id, roll_number, profiles(full_name)')
        .eq('class_id', _selected!.classModel.id);

    setState(() {
      _roster = List<Map<String, dynamic>>.from(roster);
      _scoreCtrls.clear();
      _maxScoreCtrls.clear();
      _remarkCtrls.clear();
      for (final r in _roster) {
        final id = r['student_id'] as String;
        _scoreCtrls[id] = TextEditingController();
        _maxScoreCtrls[id] = TextEditingController(text: '100');
        _remarkCtrls[id] = TextEditingController();
      }
    });
    await _applyExamConfig();
  }

  /// Module 9/10: when a formal exam is selected, look up its max/pass
  /// marks for this class+subject (from exam_subjects) so pass/fail can be
  /// auto-computed instead of relying on a free-text exam_type guess.
  Future<void> _applyExamConfig() async {
    await _loadRemarks();
    if (_selected == null || _selectedExam == null) {
      setState(() => _examSubjectConfig = null);
      return;
    }
    try {
      final config = await supabase
          .from('exam_subjects')
          .select()
          .eq('exam_id', _selectedExam!.id)
          .eq('subject_id', _selected!.subject.id)
          .eq('class_id', _selected!.classModel.id)
          .maybeSingle();
      setState(() {
        _examSubjectConfig = config;
        _examTypeCtrl.text = _selectedExam!.name;
        if (config != null) {
          final maxMarks = (config['max_marks'] as num).toString();
          for (final ctrl in _maxScoreCtrls.values) {
            ctrl.text = maxMarks;
          }
        }
      });
    } catch (_) {
      setState(() => _examSubjectConfig = null);
    }
  }

  /// Existing report-card remarks for the roster under the selected exam.
  Future<void> _loadRemarks() async {
    _savedRemarks.clear();
    for (final c in _remarkCtrls.values) {
      c.clear();
    }
    if (_selectedExam == null || _roster.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final data = await supabase
          .from('report_card_remarks')
          .select('student_id, remarks')
          .eq('exam_id', _selectedExam!.id)
          .inFilter('student_id', _remarkCtrls.keys.toList());
      for (final row in data) {
        final id = row['student_id'] as String;
        final text = row['remarks'] as String? ?? '';
        _savedRemarks[id] = text;
        _remarkCtrls[id]?.text = text;
      }
    } catch (_) {
      // Leave the fields blank; saving still works.
    }
    if (mounted) setState(() {});
  }

  bool? _passFailFor(String studentId) {
    if (_examSubjectConfig == null) return null;
    final score = double.tryParse(_scoreCtrls[studentId]?.text.trim() ?? '');
    if (score == null) return null;
    final passMarks = (_examSubjectConfig!['pass_marks'] as num).toDouble();
    return score >= passMarks;
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      final rows = <Map<String, dynamic>>[];
      for (final r in _roster) {
        final id = r['student_id'] as String;
        final scoreText = _scoreCtrls[id]?.text.trim() ?? '';
        if (scoreText.isEmpty) continue;
        final score = double.tryParse(scoreText);
        final maxScore = double.tryParse(_maxScoreCtrls[id]?.text.trim() ?? '100');
        if (score == null || maxScore == null) continue;
        rows.add({
          'student_id': id,
          'class_id': _selected!.classModel.id,
          'subject_name': _selected!.subject.name,
          'score': score,
          'max_score': maxScore,
          'exam_type': _examTypeCtrl.text.trim(),
          'exam_id': _selectedExam?.id,
          'graded_at': DateTime.now().toIso8601String(),
        });
      }

      final remarkRows = <Map<String, dynamic>>[];
      if (_selectedExam != null) {
        final now = DateTime.now().toUtc().toIso8601String();
        for (final entry in _remarkCtrls.entries) {
          final text = entry.value.text.trim();
          if (text == (_savedRemarks[entry.key] ?? '')) continue;
          remarkRows.add({
            'student_id': entry.key,
            'exam_id': _selectedExam!.id,
            'remarks': text.isEmpty ? null : text,
            'created_by': supabase.auth.currentUser?.id,
            'updated_at': now,
          });
        }
      }

      if (rows.isEmpty && remarkRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_selectedExam == null
                  ? 'Enter at least one score'
                  : 'Enter at least one score or remark')));
        }
        return;
      }

      if (rows.isNotEmpty) {
        await supabase.from(SupabaseConfig.gradesTable).upsert(
              rows,
              onConflict: 'student_id,class_id,subject_name,exam_type',
            );
        await AuditService.log(
          module: 'marks',
          action: 'save',
          newValue: {
            'class': _selected!.classModel.displayName,
            'subject': _selected!.subject.name,
            'exam_type': _examTypeCtrl.text.trim(),
            'count': rows.length,
          },
        );
      }

      if (remarkRows.isNotEmpty) {
        await supabase.from('report_card_remarks').upsert(remarkRows, onConflict: 'student_id,exam_id');
        for (final r in remarkRows) {
          _savedRemarks[r['student_id'] as String] = (r['remarks'] as String?) ?? '';
        }
        await AuditService.log(
          module: 'report_card_remarks',
          action: 'save',
          newValue: {
            'class': _selected!.classModel.displayName,
            'exam': _selectedExam!.name,
            'count': remarkRows.length,
          },
        );
      }

      if (mounted) {
        final saved = [
          if (rows.isNotEmpty) '${rows.length} grade(s)',
          if (remarkRows.isNotEmpty) '${remarkRows.length} remark(s)',
        ].join(' and ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $saved')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gradebook Input')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
              ? const Center(
                  child: Text('You are not assigned to teach any subject yet'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          DropdownButtonFormField<_Assignment>(
                            initialValue: _selected,
                            decoration: const InputDecoration(
                                labelText: 'Class · Subject'),
                            items: _assignments
                                .map((a) => DropdownMenuItem(
                                    value: a, child: Text(a.label)))
                                .toList(),
                            onChanged: (a) {
                              setState(() => _selected = a);
                              _loadRoster();
                            },
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<Exam?>(
                            initialValue: _selectedExam,
                            decoration: const InputDecoration(
                                labelText: 'Formal exam (optional — sets max/pass marks)'),
                            items: [
                              const DropdownMenuItem<Exam?>(
                                  value: null, child: Text('None (free text below)')),
                              ..._exams.map((e) => DropdownMenuItem(value: e, child: Text(e.name))),
                            ],
                            onChanged: (e) {
                              setState(() => _selectedExam = e);
                              _applyExamConfig();
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _examTypeCtrl,
                            enabled: _selectedExam == null,
                            decoration:
                                const InputDecoration(labelText: 'Exam type'),
                          ),
                          if (_selectedExam != null && _examSubjectConfig == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'No max/pass marks configured for this exam + class + subject yet — set them in Exam Management.',
                                style: TextStyle(color: Colors.orange, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _roster.isEmpty
                          ? const Center(child: Text('No students enrolled'))
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: [
                                  const DataColumn(label: Text('Student')),
                                  const DataColumn(label: Text('Roll No')),
                                  const DataColumn(label: Text('Score')),
                                  const DataColumn(label: Text('Max')),
                                  if (_examSubjectConfig != null)
                                    const DataColumn(label: Text('Result')),
                                  if (_selectedExam != null)
                                    const DataColumn(
                                      label: Tooltip(
                                        message: "Shown on the student's report card for this exam",
                                        child: Text('Report card remark'),
                                      ),
                                    ),
                                ],
                                rows: _roster.map((r) {
                                  final id = r['student_id'] as String;
                                  final name = (r['profiles'] as Map?)?['full_name']
                                          as String? ??
                                      '—';
                                  final passFail = _passFailFor(id);
                                  return DataRow(cells: [
                                    DataCell(Text(name)),
                                    DataCell(Text('${r['roll_number'] ?? '—'}')),
                                    DataCell(SizedBox(
                                      width: 70,
                                      child: TextField(
                                        controller: _scoreCtrls[id],
                                        keyboardType: TextInputType.number,
                                        decoration:
                                            const InputDecoration(isDense: true),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 70,
                                      child: TextField(
                                        controller: _maxScoreCtrls[id],
                                        keyboardType: TextInputType.number,
                                        enabled: _examSubjectConfig == null,
                                        decoration:
                                            const InputDecoration(isDense: true),
                                      ),
                                    )),
                                    if (_examSubjectConfig != null)
                                      DataCell(passFail == null
                                          ? const Text('—')
                                          : Text(
                                              passFail ? 'PASS' : 'FAIL',
                                              style: TextStyle(
                                                  color: passFail ? Colors.green : Colors.red,
                                                  fontWeight: FontWeight.bold),
                                            )),
                                    if (_selectedExam != null)
                                      DataCell(SizedBox(
                                        width: 240,
                                        child: TextField(
                                          controller: _remarkCtrls[id],
                                          maxLength: 300,
                                          decoration: const InputDecoration(
                                              isDense: true, counterText: '', hintText: 'Optional'),
                                        ),
                                      )),
                                  ]);
                                }).toList(),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                        onPressed: _saving || _roster.isEmpty ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_selectedExam == null ? 'Save Grades' : 'Save Grades & Remarks'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
