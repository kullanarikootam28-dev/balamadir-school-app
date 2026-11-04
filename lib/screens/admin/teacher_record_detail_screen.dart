import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/grade.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/models/teacher_details.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/teacher_document_service.dart';
import 'package:school_management_app/services/teacher_record_pdf_service.dart';
import 'package:school_management_app/services/teacher_records_export.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/fetch_all.dart';
import 'package:school_management_app/widgets/export_range_dialog.dart';

class TeacherRecordDetailScreen extends StatefulWidget {
  const TeacherRecordDetailScreen({super.key, required this.teacher});
  final Profile teacher;

  @override
  State<TeacherRecordDetailScreen> createState() => _TeacherRecordDetailScreenState();
}

class _TeacherRecordDetailScreenState extends State<TeacherRecordDetailScreen> {
  bool _loading = true;
  bool _saving = false;
  TeacherDetails? _details;

  final _qualificationCtrl = TextEditingController();
  final _specializationCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  DateTime? _joiningDate;
  TeacherStatus _status = TeacherStatus.active;
  final Map<String, String?> _docPaths = {};

  List<Map<String, dynamic>> _assignments = [];
  double? _averagePercent;
  int _gradeCount = 0;
  List<Map<String, dynamic>> _leaves = [];

  ReportRange _attendanceRange = ReportRange.thisMonth();
  TeacherRecordsData? _attendanceData;
  bool _attendanceLoading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _attendanceLoading = true);
    try {
      final data = await TeacherRecordsData.load(
        range: _attendanceRange,
        teacherIds: {widget.teacher.id},
      );
      if (mounted) setState(() => _attendanceData = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _attendanceLoading = false);
    }
  }

  Future<void> _pickAttendanceRange() async {
    final range = await showExportRangeDialog(context, title: 'Show attendance for');
    if (range == null) return;
    setState(() => _attendanceRange = range);
    await _loadAttendance();
  }

  Future<void> _downloadFullRecord() async {
    final range = await showExportRangeDialog(context, title: 'Download full record for');
    if (range == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final data = await TeacherRecordsData.load(range: range, teacherIds: {widget.teacher.id});
      final slug = widget.teacher.fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      await data.export('teacher_record_$slug');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildAttendanceSection() {
    final data = _attendanceData;
    final summary = data?.summaries[widget.teacher.id];
    final recent = data == null ? const <Map<String, dynamic>>[] : data.attendance.reversed.take(10).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_attendanceRange.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: _pickAttendanceRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: const Text('Change'),
                ),
              ],
            ),
            if (_attendanceLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (summary == null)
              const Text('Could not load attendance')
            else ...[
              Text(summary.percentLabel,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('Attendance over ${summary.markedDays} marked day(s)',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in kSummaryStatuses)
                    _categoryChip(categoryLabel(s), summary.counts[s] ?? 0, categoryColor(s)),
                  for (final l in kLeaveTypes)
                    _categoryChip(l, summary.leaves[l] ?? 0, categoryColor(l)),
                ],
              ),
              const SizedBox(height: 12),
              if (recent.isEmpty)
                const Text('No attendance marked in this period')
              else ...[
                Text('Recent days', style: Theme.of(context).textTheme.labelLarge),
                for (final r in recent)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.circle, size: 12, color: categoryColor(r['status'] as String)),
                    title: Text(DateFormat('EEE, d MMM').format(DateTime.parse(r['date'] as String))),
                    subtitle: Text(_scanTimes(r)),
                    trailing: Text(categoryLabel(r['status'] as String),
                        style: TextStyle(color: categoryColor(r['status'] as String))),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _scanTimes(Map<String, dynamic> r) {
    final parts = [
      if (r['check_in_time'] != null) 'In ${TeacherRecordsData.localTime(r['check_in_time'])}',
      if (r['check_out_time'] != null) 'Out ${TeacherRecordsData.localTime(r['check_out_time'])}',
    ];
    return parts.isEmpty ? 'No scan times (marked manually)' : parts.join(' · ');
  }

  Widget _categoryChip(String label, int count, Color color) => Chip(
        label: Text('$label: $count'),
        backgroundColor: color.withValues(alpha: 0.12),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      );

  @override
  void dispose() {
    _qualificationCtrl.dispose();
    _specializationCtrl.dispose();
    _experienceCtrl.dispose();
    _remarksCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from('teacher_details')
            .select()
            .eq('teacher_id', widget.teacher.id)
            .maybeSingle(),
        supabase
            .from('class_subject_teachers')
            .select('classes(grade, section), subjects(name)')
            .eq('teacher_id', widget.teacher.id),
        supabase
            .from(SupabaseConfig.classesTable)
            .select('grade, section')
            .eq('teacher_id', widget.teacher.id),
        supabase
            .from('teacher_leaves')
            .select()
            .eq('teacher_id', widget.teacher.id)
            .order('leave_date', ascending: false),
      ]);

      final detailsRow = results[0] as Map<String, dynamic>?;
      if (detailsRow != null) {
        final d = TeacherDetails.fromJson(detailsRow);
        _details = d;
        _qualificationCtrl.text = d.qualification ?? '';
        _specializationCtrl.text = d.specialization ?? '';
        _experienceCtrl.text = d.experienceYears?.toString() ?? '';
        _remarksCtrl.text = d.remarks ?? '';
        _addressCtrl.text = d.address ?? '';
        _joiningDate = d.joiningDate;
        _status = d.status;
        _docPaths['resume'] = d.resumeUrl;
        _docPaths['certificate'] = d.certificateUrl;
        _docPaths['id_proof'] = d.idProofUrl;
      }

      final subjectAssignments = List<Map<String, dynamic>>.from(results[1] as List);
      final homeroomAssignments = (results[2] as List)
          .cast<Map<String, dynamic>>()
          .map((c) => {'classes': c, 'subjects': {'name': 'Homeroom'}})
          .toList();
      setState(() {
        _assignments = [...subjectAssignments, ...homeroomAssignments];
        _leaves = List<Map<String, dynamic>>.from(results[3] as List);
      });

      await _computePerformance();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Same averaging logic as rankings_screen.dart's teacher tab, computed
  /// here for just this one teacher.
  Future<void> _computePerformance() async {
    try {
      final results = await Future.wait([
        supabase.from('classes').select('id').eq('teacher_id', widget.teacher.id),
        supabase
            .from('class_subject_teachers')
            .select('class_id, subjects(name)')
            .eq('teacher_id', widget.teacher.id),
      ]);

      final homeroomClassIds = (results[0] as List)
          .cast<Map<String, dynamic>>()
          .map((c) => c['id'] as String)
          .toSet();
      final assignments = (results[1] as List).cast<Map<String, dynamic>>();
      final subjectAssignmentKeys = assignments.map((row) {
        final subjectName = (row['subjects'] as Map?)?['name'] as String?;
        return '${row['class_id']}|$subjectName';
      }).toSet();
      final classIds = {...homeroomClassIds, ...assignments.map((a) => a['class_id'] as String)};
      if (classIds.isEmpty) return;

      // Only this teacher's classes, paged — the whole-school grades table
      // outgrows the server's 1000-row response cap.
      final gradeRows = await fetchAllRows(() => supabase
          .from('grades')
          .select('id, class_id, subject_name, score, max_score')
          .inFilter('class_id', classIds.toList())
          .order('id'));
      final grades =
          gradeRows.map((e) => Grade.fromJson({...e, 'student_id': ''})).toList();

      final relevant = grades.where((g) {
        return subjectAssignmentKeys.contains('${g.classId}|${g.subjectName}') ||
            homeroomClassIds.contains(g.classId);
      }).toList();

      if (relevant.isNotEmpty) {
        final avg = relevant.map((g) => g.percentage).reduce((a, b) => a + b) / relevant.length;
        setState(() {
          _averagePercent = avg;
          _gradeCount = relevant.length;
        });
      }
    } catch (_) {
      // Performance metrics are a nice-to-have; leave unset on failure.
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'teacher_id': widget.teacher.id,
        'qualification': _qualificationCtrl.text.trim().isEmpty ? null : _qualificationCtrl.text.trim(),
        'specialization': _specializationCtrl.text.trim().isEmpty ? null : _specializationCtrl.text.trim(),
        'experience_years':
            _experienceCtrl.text.trim().isEmpty ? null : int.tryParse(_experienceCtrl.text.trim()),
        'joining_date': _joiningDate?.toIso8601String().substring(0, 10),
        'status': TeacherDetails.statusToJson(_status),
        'remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      };
      await supabase.from('teacher_details').upsert(payload, onConflict: 'teacher_id');
      await AuditService.log(
        module: 'teacher_records',
        action: _details == null ? 'create' : 'update',
        oldValue: _details?.toJson(),
        newValue: payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
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

  Future<void> _uploadDoc(String docType) async {
    try {
      final path = await TeacherDocumentService.pickAndUpload(
        teacherId: widget.teacher.id,
        docType: docType,
      );
      if (path != null) {
        setState(() => _docPaths[docType] = path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${TeacherDocumentService.docTypeLabels[docType]} uploaded')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _logLeave() async {
    String leaveType = 'CL';
    DateTime leaveDate = DateTime.now();
    final remarksCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Log Leave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: leaveType,
                decoration: const InputDecoration(labelText: 'Leave type'),
                items: const [
                  DropdownMenuItem(value: 'CL', child: Text('CL — 1 day/month, no salary deduction')),
                  DropdownMenuItem(value: 'LP', child: Text('LP — ₹500 (not tracked in salary)')),
                ],
                onChanged: (v) => setDialogState(() => leaveType = v!),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(DateFormat('d MMM yyyy').format(leaveDate)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: leaveDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() => leaveDate = picked);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarksCtrl,
                decoration: const InputDecoration(labelText: 'Remarks (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Leave')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('teacher_leaves').insert({
        'teacher_id': widget.teacher.id,
        'leave_type': leaveType,
        'leave_date': leaveDate.toIso8601String().substring(0, 10),
        'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
        'marked_by': supabase.auth.currentUser?.id,
      });
      await AuditService.log(
        module: 'teacher_leaves',
        action: 'create',
        newValue: {'teacher_id': widget.teacher.id, 'leave_type': leaveType, 'leave_date': leaveDate.toIso8601String()},
      );
      await Future.wait([_load(), _loadAttendance()]);
    } catch (e) {
      if (mounted) {
        final message = (e is PostgrestException && e.code == '23505' && leaveType == 'CL')
            ? 'Only one CL is allowed per month.'
            : friendlyErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _exportPdf() async {
    try {
      await TeacherRecordPdfService.downloadRecord(
        fullName: widget.teacher.fullName,
        email: widget.teacher.email,
        phone: widget.teacher.phone,
        qualification: _qualificationCtrl.text.trim(),
        specialization: _specializationCtrl.text.trim(),
        experienceYears: _experienceCtrl.text.trim(),
        joiningDate: _joiningDate,
        status: _status.name,
        assignments: _assignments,
        averagePercent: _averagePercent,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title,
            style:
                Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teacher.fullName),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_outlined),
            tooltip: 'Download full record (Excel / Google Sheets)',
            onPressed: _exporting ? null : _downloadFullRecord,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Export PDF',
            onPressed: _loading ? null : _exportPdf,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.teacher.fullName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(widget.teacher.email),
                        if (widget.teacher.phone != null) Text(widget.teacher.phone!),
                      ],
                    ),
                  ),
                ),
                _sectionTitle('Performance metrics'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _averagePercent == null
                        ? const Text('No grades recorded yet for this teacher\'s classes/subjects')
                        : Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${_averagePercent!.toStringAsFixed(1)}%',
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                                    Text('Average score across $_gradeCount recorded grade(s)',
                                        style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                _sectionTitle('Attendance'),
                _buildAttendanceSection(),
                _sectionTitle('Assigned subjects & classes'),
                if (_assignments.isEmpty)
                  const Text('No subject or homeroom assignments yet')
                else
                  ..._assignments.map((a) {
                    final cls = a['classes'] as Map?;
                    final subject = (a['subjects'] as Map?)?['name'] as String? ?? '—';
                    final className = cls != null ? 'Grade ${cls['grade']} – ${cls['section']}' : '—';
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.class_outlined),
                        title: Text(className),
                        subtitle: Text(subject),
                      ),
                    );
                  }),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle('Leave'),
                    TextButton.icon(
                      onPressed: _logLeave,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Log Leave'),
                    ),
                  ],
                ),
                if (_leaves.isEmpty)
                  const Text('No leave recorded yet')
                else
                  ..._leaves.map((l) {
                    final type = l['leave_type'] as String;
                    final date = DateTime.parse(l['leave_date'] as String);
                    final remarks = l['remarks'] as String?;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          type == 'CL' ? Icons.event_available : Icons.event_busy,
                          color: type == 'CL' ? Colors.green : Colors.orange,
                        ),
                        title: Text('$type — ${DateFormat('d MMM yyyy').format(date)}'),
                        subtitle: Text(
                          type == 'LP'
                              ? 'LP — ₹500 (not deducted from any stored salary)${remarks != null ? '\n$remarks' : ''}'
                              : (remarks ?? 'No salary deduction'),
                        ),
                        isThreeLine: type == 'LP' && remarks != null,
                      ),
                    );
                  }),
                _sectionTitle('Professional details'),
                TextField(
                  controller: _qualificationCtrl,
                  decoration: const InputDecoration(labelText: 'Qualification', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _specializationCtrl,
                  decoration: const InputDecoration(labelText: 'Subject specialization', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _experienceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Years of experience', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date of joining'),
                  subtitle: Text(_joiningDate != null ? DateFormat('d MMM yyyy').format(_joiningDate!) : 'Not set'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _joiningDate ?? DateTime.now(),
                      firstDate: DateTime(1990),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _joiningDate = picked);
                  },
                ),
                DropdownButtonFormField<TeacherStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: TeacherStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.name.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _remarksCtrl,
                  decoration: const InputDecoration(labelText: 'Remarks (optional)', border: OutlineInputBorder()),
                ),
                _sectionTitle('Documents'),
                for (final docType in TeacherDocumentService.docTypeLabels.keys)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _docPaths[docType] != null ? Icons.check_circle : Icons.upload_file_outlined,
                        color: _docPaths[docType] != null ? Colors.green : null,
                      ),
                      title: Text(TeacherDocumentService.docTypeLabels[docType]!),
                      subtitle: Text(_docPaths[docType] ?? 'Not uploaded'),
                      trailing: TextButton(
                        onPressed: () => _uploadDoc(docType),
                        child: Text(_docPaths[docType] != null ? 'Replace' : 'Upload'),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Details'),
                ),
              ],
            ),
    );
  }
}
