import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/models/student_details.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/document_upload_service.dart';
import 'package:school_management_app/services/student_records_export.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/widgets/export_range_dialog.dart';

/// Parent/guardian and demographic record-keeping (module 1 + 2 of the
/// client spec), grounded in the school's real EMIS export field names
/// (EMIS Id, Admission Number, Father/Mother/Guardian details, Aadhaar,
/// Address, Blood Group, Religion, Medium of Instruction, Community,
/// Mother Tongue) — see migration 010_erp_expansion.sql / student_details.
class StudentRecordsScreen extends StatefulWidget {
  const StudentRecordsScreen({super.key});

  @override
  State<StudentRecordsScreen> createState() => _StudentRecordsScreenState();
}

const _kRecordDocTypes = ['photo', 'birth_certificate', 'aadhaar', 'tc'];

class _StudentRecordsScreenState extends State<StudentRecordsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<Profile> _students = [];
  Map<String, String> _classLabelByStudent = {};
  Map<String, Map<String, String?>> _docPathsByStudent = {};
  String _query = '';
  String _recordsQuery = '';
  String _recordsFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'student')
            .order('full_name'),
        supabase.from('class_students').select('student_id, classes(grade, section)'),
        supabase
            .from('student_details')
            .select('student_id, photo_url, birth_certificate_url, aadhaar_doc_url, tc_url'),
      ]);
      final enrollments = (results[1] as List).cast<Map<String, dynamic>>();
      final labels = <String, String>{};
      for (final row in enrollments) {
        final cls = row['classes'] as Map?;
        if (cls != null) {
          labels[row['student_id'] as String] = 'Grade ${cls['grade']} – ${cls['section']}';
        }
      }
      final docRows = (results[2] as List).cast<Map<String, dynamic>>();
      final docPaths = <String, Map<String, String?>>{};
      for (final row in docRows) {
        docPaths[row['student_id'] as String] = {
          'photo': row['photo_url'] as String?,
          'birth_certificate': row['birth_certificate_url'] as String?,
          'aadhaar': row['aadhaar_doc_url'] as String?,
          'tc': row['tc_url'] as String?,
        };
      }
      setState(() {
        _students = (results[0] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList();
        _classLabelByStudent = labels;
        _docPathsByStudent = docPaths;
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

  bool _exporting = false;

  /// Full structured workbook (demographics, parent/guardian details,
  /// attendance by category, fee totals, average score per subject) for the
  /// students currently shown on the Students tab — the search filter
  /// applies.
  Future<void> _exportAll() async {
    final range = await showExportRangeDialog(context, title: 'Attendance for');
    if (range == null || !mounted) return;
    final filtered = _query.isEmpty
        ? _students
        : _students
            .where((s) => s.fullName.toLowerCase().contains(_query.toLowerCase()) ||
                s.email.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    setState(() => _exporting = true);
    try {
      final data = await StudentRecordsData.load(
        range: range,
        studentIds: filtered.map((s) => s.id).toSet(),
      );
      await data.export('student_records');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openStudent(Profile s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _StudentDetailsEditScreen(student: s)),
    );
    await _load();
  }

  Widget _buildStudentsTab() {
    final filtered = _query.isEmpty
        ? _students
        : _students
            .where((s) => s.fullName.toLowerCase().contains(_query.toLowerCase()) ||
                s.email.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name or email...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No students found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = filtered[i];
                      final classLabel = _classLabelByStudent[s.id];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text(s.fullName[0])),
                          title: Text(s.fullName),
                          subtitle: Text('${s.email}\n${classLabel ?? 'No class assigned'}'),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openStudent(s),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRecordsTab() {
    var filtered = _recordsQuery.isEmpty
        ? _students
        : _students
            .where((s) => s.fullName.toLowerCase().contains(_recordsQuery.toLowerCase()))
            .toList();

    if (_recordsFilter != 'all') {
      if (_recordsFilter == 'complete') {
        filtered = filtered.where((s) {
          final docs = _docPathsByStudent[s.id];
          return docs != null && _kRecordDocTypes.every((t) => docs[t] != null);
        }).toList();
      } else {
        // 'missing_<docType>'
        final docType = _recordsFilter.substring('missing_'.length);
        filtered = filtered.where((s) => _docPathsByStudent[s.id]?[docType] == null).toList();
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search by student name...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _recordsQuery = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _recordsFilter == 'all',
                onSelected: (_) => setState(() => _recordsFilter = 'all'),
              ),
              ChoiceChip(
                label: const Text('Fully complete'),
                selected: _recordsFilter == 'complete',
                onSelected: (_) => setState(() => _recordsFilter = 'complete'),
              ),
              for (final docType in _kRecordDocTypes)
                ChoiceChip(
                  label: Text('Missing ${DocumentUploadService.docTypeLabels[docType]}'),
                  selected: _recordsFilter == 'missing_$docType',
                  onSelected: (_) => setState(() => _recordsFilter = 'missing_$docType'),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No students match this filter'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = filtered[i];
                      final docs = _docPathsByStudent[s.id] ?? {};
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text(s.fullName[0])),
                          title: Text(s.fullName),
                          subtitle: Text(_classLabelByStudent[s.id] ?? 'No class assigned'),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              for (final docType in _kRecordDocTypes)
                                Tooltip(
                                  message:
                                      '${DocumentUploadService.docTypeLabels[docType]}: ${docs[docType] != null ? 'Uploaded' : 'Missing'}',
                                  child: Icon(
                                    docs[docType] != null
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    size: 18,
                                    color: docs[docType] != null ? Colors.green : Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _openStudent(s),
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
        title: const Text('Student Records'),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_outlined),
            tooltip: 'Export records & attendance (Excel / Google Sheets)',
            onPressed: _students.isEmpty || _exporting ? null : _exportAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'Students'), Tab(text: 'Document Records')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildStudentsTab(), _buildRecordsTab()],
            ),
    );
  }
}

class _StudentDetailsEditScreen extends StatefulWidget {
  const _StudentDetailsEditScreen({required this.student});
  final Profile student;

  @override
  State<_StudentDetailsEditScreen> createState() => _StudentDetailsEditScreenState();
}

class _StudentDetailsEditScreenState extends State<_StudentDetailsEditScreen> {
  bool _loading = true;
  bool _saving = false;
  StudentDetails? _details;

  final _emisCtrl = TextEditingController();
  final _admissionCtrl = TextEditingController();
  final _fatherNameCtrl = TextEditingController();
  final _fatherOccCtrl = TextEditingController();
  final _fatherEduCtrl = TextEditingController();
  final _motherNameCtrl = TextEditingController();
  final _motherOccCtrl = TextEditingController();
  final _motherEduCtrl = TextEditingController();
  final _guardianNameCtrl = TextEditingController();
  final _guardianOccCtrl = TextEditingController();
  final _aadhaarCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _pinCodeCtrl = TextEditingController();
  final _bloodGroupCtrl = TextEditingController();
  final _religionCtrl = TextEditingController();
  final _mediumCtrl = TextEditingController();
  final _communityCtrl = TextEditingController();
  final _motherTongueCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  DateTime? _dob;
  DateTime? _dateOfJoining;
  String? _gender;
  StudentStatus _status = StudentStatus.active;
  final Map<String, String?> _docPaths = {};

  final _rollNumberCtrl = TextEditingController();
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  String? _enrollmentId;

  ReportRange _overviewRange = ReportRange.thisMonth();
  StudentRecordsData? _overviewData;
  bool _overviewLoading = true;
  bool _exportingRecord = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOverview();
  }

  @override
  void dispose() {
    for (final c in [
      _emisCtrl, _admissionCtrl, _fatherNameCtrl, _fatherOccCtrl, _fatherEduCtrl,
      _motherNameCtrl, _motherOccCtrl, _motherEduCtrl, _guardianNameCtrl, _guardianOccCtrl,
      _aadhaarCtrl, _addressCtrl, _pinCodeCtrl, _bloodGroupCtrl, _religionCtrl,
      _mediumCtrl, _communityCtrl, _motherTongueCtrl, _emergencyNameCtrl, _emergencyPhoneCtrl,
      _rollNumberCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        supabase.from('student_details').select().eq('student_id', widget.student.id).maybeSingle(),
        supabase.from(SupabaseConfig.classesTable).select().order('grade'),
        supabase
            .from('class_students')
            .select('id, class_id, roll_number')
            .eq('student_id', widget.student.id)
            .maybeSingle(),
      ]);
      _classes = (results[1] as List)
          .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final enrollment = results[2] as Map<String, dynamic>?;
      if (enrollment != null && _classes.isNotEmpty) {
        _enrollmentId = enrollment['id'] as String;
        _selectedClass = _classes.firstWhere(
          (c) => c.id == enrollment['class_id'],
          orElse: () => _classes.first,
        );
        _rollNumberCtrl.text = enrollment['roll_number'] as String? ?? '';
      }
      final data = results[0] as Map<String, dynamic>?;
      if (data != null) {
        final d = StudentDetails.fromJson(data);
        _details = d;
        _emisCtrl.text = d.emisId ?? '';
        _admissionCtrl.text = d.admissionNumber ?? '';
        _fatherNameCtrl.text = d.fatherName ?? '';
        _fatherOccCtrl.text = d.fatherOccupation ?? '';
        _fatherEduCtrl.text = d.fatherEducation ?? '';
        _motherNameCtrl.text = d.motherName ?? '';
        _motherOccCtrl.text = d.motherOccupation ?? '';
        _motherEduCtrl.text = d.motherEducation ?? '';
        _guardianNameCtrl.text = d.guardianName ?? '';
        _guardianOccCtrl.text = d.guardianOccupation ?? '';
        _aadhaarCtrl.text = d.aadhaarNumber ?? '';
        _addressCtrl.text = d.address ?? '';
        _pinCodeCtrl.text = d.pinCode ?? '';
        _bloodGroupCtrl.text = d.bloodGroup ?? '';
        _religionCtrl.text = d.religion ?? '';
        _mediumCtrl.text = d.mediumOfInstruction ?? '';
        _communityCtrl.text = d.community ?? '';
        _motherTongueCtrl.text = d.motherTongue ?? '';
        _emergencyNameCtrl.text = d.emergencyContactName ?? '';
        _emergencyPhoneCtrl.text = d.emergencyContactPhone ?? '';
        _dob = d.dateOfBirth;
        _dateOfJoining = d.dateOfJoining;
        _gender = d.gender;
        _status = d.status;
        _docPaths['photo'] = d.photoUrl;
        _docPaths['birth_certificate'] = d.birthCertificateUrl;
        _docPaths['aadhaar'] = d.aadhaarDocUrl;
        _docPaths['tc'] = d.tcUrl;
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

  Future<void> _loadOverview() async {
    setState(() => _overviewLoading = true);
    try {
      final data = await StudentRecordsData.load(
        range: _overviewRange,
        studentIds: {widget.student.id},
      );
      if (mounted) setState(() => _overviewData = data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _overviewLoading = false);
    }
  }

  Future<void> _pickOverviewRange() async {
    final range = await showExportRangeDialog(context, title: 'Attendance for');
    if (range == null || !mounted) return;
    setState(() => _overviewRange = range);
    await _loadOverview();
  }

  Future<void> _downloadFullRecord() async {
    final data = _overviewData;
    if (data == null) return;
    setState(() => _exportingRecord = true);
    try {
      await data.export('student_record_${widget.student.fullName.replaceAll(' ', '_')}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _exportingRecord = false);
    }
  }

  Widget _categoryChip(String key, int count) => Chip(
        label: Text('${categoryLabel(key)}: $count'),
        backgroundColor: categoryColor(key).withValues(alpha: 0.12),
        labelStyle: TextStyle(color: categoryColor(key), fontWeight: FontWeight.w600, fontSize: 12),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _buildOverviewSection() {
    if (_overviewLoading || _overviewData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final data = _overviewData!;
    final summary = data.attendanceSummaries[widget.student.id]!;
    final fees = data.feeTotalsOf(widget.student.id);
    final grades = data.gradesBySubject(widget.student.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Attendance for ${_overviewRange.label}')),
            TextButton(onPressed: _pickOverviewRange, child: const Text('Change')),
          ],
        ),
        Row(
          children: [
            Text(summary.percentLabel,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(width: 8),
            Text('${summary.markedDays} day(s) marked', style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in kSummaryStatuses)
              if (summary.counts[s]! > 0) _categoryChip(s, summary.counts[s]!),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Fees (all-time)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text('Paid: ₹${(fees['paid']! / 100).toStringAsFixed(2)}'),
              backgroundColor: Colors.green.withValues(alpha: 0.12),
              labelStyle: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
            Chip(
              label: Text('Pending: ₹${(fees['pending']! / 100).toStringAsFixed(2)}'),
              backgroundColor: Colors.orange.withValues(alpha: 0.12),
              labelStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
            ),
            if (fees['waived']! > 0)
              Chip(
                label: Text('Waived: ₹${(fees['waived']! / 100).toStringAsFixed(2)}'),
                backgroundColor: Colors.blueGrey.withValues(alpha: 0.12),
                labelStyle: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Average score by subject', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        grades.isEmpty
            ? const Text('No grades recorded yet', style: TextStyle(color: Colors.grey))
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in grades.entries)
                    Chip(
                      label: Text('${entry.key}: ${entry.value.$1.toStringAsFixed(1)}% '
                          '(${entry.value.$2})'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'student_id': widget.student.id,
        'emis_id': _emisCtrl.text.trim().isEmpty ? null : _emisCtrl.text.trim(),
        'admission_number':
            _admissionCtrl.text.trim().isEmpty ? null : _admissionCtrl.text.trim(),
        'father_name': _fatherNameCtrl.text.trim().isEmpty ? null : _fatherNameCtrl.text.trim(),
        'father_occupation':
            _fatherOccCtrl.text.trim().isEmpty ? null : _fatherOccCtrl.text.trim(),
        'father_education':
            _fatherEduCtrl.text.trim().isEmpty ? null : _fatherEduCtrl.text.trim(),
        'mother_name': _motherNameCtrl.text.trim().isEmpty ? null : _motherNameCtrl.text.trim(),
        'mother_occupation':
            _motherOccCtrl.text.trim().isEmpty ? null : _motherOccCtrl.text.trim(),
        'mother_education':
            _motherEduCtrl.text.trim().isEmpty ? null : _motherEduCtrl.text.trim(),
        'guardian_name':
            _guardianNameCtrl.text.trim().isEmpty ? null : _guardianNameCtrl.text.trim(),
        'guardian_occupation':
            _guardianOccCtrl.text.trim().isEmpty ? null : _guardianOccCtrl.text.trim(),
        'aadhaar_number': _aadhaarCtrl.text.trim().isEmpty ? null : _aadhaarCtrl.text.trim(),
        'date_of_birth': _dob?.toIso8601String().substring(0, 10),
        'gender': _gender,
        'date_of_joining': _dateOfJoining?.toIso8601String().substring(0, 10),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'pin_code': _pinCodeCtrl.text.trim().isEmpty ? null : _pinCodeCtrl.text.trim(),
        'blood_group': _bloodGroupCtrl.text.trim().isEmpty ? null : _bloodGroupCtrl.text.trim(),
        'religion': _religionCtrl.text.trim().isEmpty ? null : _religionCtrl.text.trim(),
        'medium_of_instruction':
            _mediumCtrl.text.trim().isEmpty ? null : _mediumCtrl.text.trim(),
        'community': _communityCtrl.text.trim().isEmpty ? null : _communityCtrl.text.trim(),
        'mother_tongue':
            _motherTongueCtrl.text.trim().isEmpty ? null : _motherTongueCtrl.text.trim(),
        'emergency_contact_name':
            _emergencyNameCtrl.text.trim().isEmpty ? null : _emergencyNameCtrl.text.trim(),
        'emergency_contact_phone':
            _emergencyPhoneCtrl.text.trim().isEmpty ? null : _emergencyPhoneCtrl.text.trim(),
        'status': _status.name,
      };
      await supabase.from('student_details').upsert(payload);
      await AuditService.log(
        module: 'student_records',
        action: _details == null ? 'create' : 'update',
        oldValue: _details?.toJson(),
        newValue: payload,
      );

      if (_selectedClass != null) {
        final enrollmentPayload = {
          'class_id': _selectedClass!.id,
          'roll_number': _rollNumberCtrl.text.trim().isEmpty ? null : _rollNumberCtrl.text.trim(),
        };
        if (_enrollmentId != null) {
          await supabase.from('class_students').update(enrollmentPayload).eq('id', _enrollmentId!);
        } else {
          final created = await supabase
              .from('class_students')
              .insert({'student_id': widget.student.id, ...enrollmentPayload})
              .select()
              .single();
          _enrollmentId = created['id'] as String;
        }
        await AuditService.log(
          module: 'student_records',
          action: 'class_change',
          newValue: {'student_id': widget.student.id, ...enrollmentPayload},
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
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
      final path = await DocumentUploadService.pickAndUpload(
        studentId: widget.student.id,
        docType: docType,
      );
      if (path != null) {
        setState(() => _docPaths[docType] = path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${DocumentUploadService.docTypeLabels[docType]} uploaded')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _pickDate({required bool isDob}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isDob ? _dob : _dateOfJoining) ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isDob ? _dob = picked : _dateOfJoining = picked);
    }
  }

  Widget _field(TextEditingController ctrl, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(title,
            style:
                Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.student.fullName),
        actions: [
          IconButton(
            icon: _exportingRecord
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_outlined),
            tooltip: 'Download full record (Excel / Google Sheets)',
            onPressed: _overviewData == null || _exportingRecord ? null : _downloadFullRecord,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
                _sectionTitle('Class'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<ClassModel>(
                        initialValue: _selectedClass,
                        decoration: const InputDecoration(labelText: 'Class'),
                        items: _classes
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedClass = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _rollNumberCtrl,
                        decoration: const InputDecoration(labelText: 'Roll number'),
                      ),
                    ),
                  ],
                ),
                _sectionTitle('Overview'),
                _buildOverviewSection(),
                _sectionTitle('Identifiers'),
                _field(_emisCtrl, 'EMIS Id'),
                _field(_admissionCtrl, 'Admission Number'),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _gender,
                        decoration: const InputDecoration(labelText: 'Gender'),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Date of birth'),
                        subtitle: Text(_dob != null ? DateFormat('d MMM yyyy').format(_dob!) : '—'),
                        onTap: () => _pickDate(isDob: true),
                      ),
                    ),
                  ],
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date of joining'),
                  subtitle: Text(
                      _dateOfJoining != null ? DateFormat('d MMM yyyy').format(_dateOfJoining!) : '—'),
                  onTap: () => _pickDate(isDob: false),
                ),
                DropdownButtonFormField<StudentStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: StudentStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.name.toUpperCase())))
                      .toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
                _sectionTitle('Father'),
                _field(_fatherNameCtrl, 'Father name'),
                _field(_fatherOccCtrl, 'Father occupation'),
                _field(_fatherEduCtrl, 'Father education'),
                _sectionTitle('Mother'),
                _field(_motherNameCtrl, 'Mother name'),
                _field(_motherOccCtrl, 'Mother occupation'),
                _field(_motherEduCtrl, 'Mother education'),
                _sectionTitle('Guardian (if applicable)'),
                _field(_guardianNameCtrl, 'Guardian name'),
                _field(_guardianOccCtrl, 'Guardian occupation'),
                _sectionTitle('Emergency contact'),
                _field(_emergencyNameCtrl, 'Emergency contact name'),
                _field(_emergencyPhoneCtrl, 'Emergency contact phone'),
                _sectionTitle('Demographics & address'),
                _field(_aadhaarCtrl, 'Aadhaar number'),
                _field(_addressCtrl, 'Address'),
                _field(_pinCodeCtrl, 'Pin code'),
                _field(_bloodGroupCtrl, 'Blood group'),
                _field(_religionCtrl, 'Religion'),
                _field(_mediumCtrl, 'Medium of instruction'),
                _field(_communityCtrl, 'Community'),
                _field(_motherTongueCtrl, 'Mother tongue'),
                _sectionTitle('Documents'),
                for (final docType in DocumentUploadService.docTypeLabels.keys)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _docPaths[docType] != null
                            ? Icons.check_circle
                            : Icons.upload_file_outlined,
                        color: _docPaths[docType] != null ? Colors.green : null,
                      ),
                      title: Text(DocumentUploadService.docTypeLabels[docType]!),
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
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Details'),
                ),
              ],
            ),
    );
  }
}
