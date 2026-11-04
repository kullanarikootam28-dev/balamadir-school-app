import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/fetch_all.dart';
import 'package:school_management_app/widgets/export_range_dialog.dart';

/// Everything the admin knows about a set of students for one period:
/// demographics + parent/guardian details, class & roll number, attendance
/// by category (in [range]), fee totals (all-time — a running balance, not
/// a period activity log), and average score per subject (all-time).
/// Shared by the Student Records list export and the read-only Overview
/// section on a student's own record.
class StudentRecordsData {
  StudentRecordsData._({
    required this.range,
    required this.students,
    required this.details,
    required this.enrollment,
    required this.attendance,
    required this.feePayments,
    required this.grades,
  });

  final ReportRange range;
  final List<Map<String, dynamic>> students; // id, full_name, email, phone
  final Map<String, Map<String, dynamic>> details; // student_id -> student_details row
  final Map<String, Map<String, dynamic>> enrollment; // student_id -> {roll_number, classes: {grade, section}}
  final List<Map<String, dynamic>> attendance; // in range
  final List<Map<String, dynamic>> feePayments; // all-time
  final List<Map<String, dynamic>> grades; // all-time

  String nameOf(String studentId) => students
      .firstWhere((s) => s['id'] == studentId, orElse: () => const {'full_name': '—'})['full_name'] as String;

  String classLabelOf(String studentId) {
    final cls = enrollment[studentId]?['classes'] as Map?;
    return cls == null ? '—' : 'Grade ${cls['grade']} – ${cls['section']}';
  }

  String rollNoOf(String studentId) => (enrollment[studentId]?['roll_number'] as String?) ?? '—';

  /// One summary per student (every student in [students], even with no
  /// marked days).
  Map<String, AttendanceSummary> get attendanceSummaries {
    final out = {for (final s in students) s['id'] as String: AttendanceSummary()};
    for (final r in attendance) {
      out[r['student_id']]?.addStatus(r['status'] as String);
    }
    return out;
  }

  /// Paid / pending (pending + overdue) / waived, in paise — the same
  /// status grouping fee_management_screen.dart uses for its own totals.
  Map<String, int> feeTotalsOf(String studentId) {
    var paid = 0, pending = 0, waived = 0;
    for (final p in feePayments) {
      if (p['student_id'] != studentId) continue;
      final amount = p['amount_paise'] as int;
      switch (p['status'] as String) {
        case 'paid':
          paid += amount;
          break;
        case 'pending':
        case 'overdue':
          pending += amount;
          break;
        case 'waived':
          waived += amount;
          break;
      }
    }
    return {'paid': paid, 'pending': pending, 'waived': waived};
  }

  /// Average % per subject for one student, subject name -> (average, count).
  Map<String, (double, int)> gradesBySubject(String studentId) {
    final bySubject = <String, List<double>>{};
    for (final g in grades) {
      if (g['student_id'] != studentId) continue;
      final max = (g['max_score'] as num).toDouble();
      if (max == 0) continue;
      final pct = (g['score'] as num).toDouble() / max * 100;
      bySubject.putIfAbsent(g['subject_name'] as String, () => []).add(pct);
    }
    return {
      for (final entry in bySubject.entries)
        entry.key: (entry.value.reduce((a, b) => a + b) / entry.value.length, entry.value.length),
    };
  }

  static Future<StudentRecordsData> load({required ReportRange range, Set<String>? studentIds}) async {
    final ids = studentIds?.toList();
    final results = await Future.wait<dynamic>([
      fetchAllRows(() {
        final q = supabase.from('profiles').select('id, full_name, email, phone').eq('role', 'student');
        return (ids == null ? q : q.inFilter('id', ids)).order('full_name', ascending: true).order('id');
      }),
      fetchAllRows(() {
        final q = supabase.from('student_details').select();
        return (ids == null ? q : q.inFilter('student_id', ids)).order('student_id');
      }),
      fetchAllRows(() {
        final q = supabase.from('class_students').select('student_id, roll_number, classes(grade, section)');
        return (ids == null ? q : q.inFilter('student_id', ids)).order('student_id');
      }),
      fetchAllRows(() {
        final q = supabase
            .from('attendance')
            .select('id, date, status, student_id')
            .gte('date', range.startIso)
            .lt('date', range.endIso);
        return (ids == null ? q : q.inFilter('student_id', ids)).order('date', ascending: true).order('id');
      }),
      fetchAllRows(() {
        final q = supabase
            .from('fee_payments')
            .select('id, student_id, amount_paise, status, due_date, paid_at, description, payment_mode');
        return (ids == null ? q : q.inFilter('student_id', ids)).order('due_date', ascending: false).order('id');
      }),
      fetchAllRows(() {
        final q = supabase.from('grades').select('id, student_id, subject_name, score, max_score, graded_at');
        return (ids == null ? q : q.inFilter('student_id', ids)).order('id');
      }),
    ]);

    return StudentRecordsData._(
      range: range,
      students: results[0] as List<Map<String, dynamic>>,
      details: {
        for (final d in results[1] as List<Map<String, dynamic>>) d['student_id'] as String: d,
      },
      enrollment: {
        for (final e in results[2] as List<Map<String, dynamic>>) e['student_id'] as String: e,
      },
      attendance: results[3] as List<Map<String, dynamic>>,
      feePayments: results[4] as List<Map<String, dynamic>>,
      grades: results[5] as List<Map<String, dynamic>>,
    );
  }

  static String _date(Object? iso) =>
      iso == null ? '' : DateFormat('dd-MM-yyyy').format(DateTime.parse(iso as String));

  static String _rupees(int paise) => (paise / 100).toStringAsFixed(2);

  List<ExportSheet> toSheets() {
    final attSummaries = attendanceSummaries;

    return [
      ExportSheet(
        name: 'Students',
        headers: const [
          'Name', 'Email', 'Phone', 'Class', 'Roll No', 'EMIS Id', 'Admission No', 'Gender',
          'Date of birth', 'Date of joining', 'Father name', 'Father occupation', 'Mother name',
          'Mother occupation', 'Guardian name', 'Aadhaar number', 'Address', 'Pin code',
          'Blood group', 'Religion', 'Medium of instruction', 'Community', 'Mother tongue',
          'Emergency contact name', 'Emergency contact phone', 'Status',
        ],
        rows: [
          for (final s in students)
            () {
              final d = details[s['id']] ?? const <String, dynamic>{};
              return [
                s['full_name'],
                s['email'],
                s['phone'] ?? '',
                classLabelOf(s['id'] as String),
                rollNoOf(s['id'] as String),
                d['emis_id'] ?? '',
                d['admission_number'] ?? '',
                d['gender'] ?? '',
                _date(d['date_of_birth']),
                _date(d['date_of_joining']),
                d['father_name'] ?? '',
                d['father_occupation'] ?? '',
                d['mother_name'] ?? '',
                d['mother_occupation'] ?? '',
                d['guardian_name'] ?? '',
                d['aadhaar_number'] ?? '',
                d['address'] ?? '',
                d['pin_code'] ?? '',
                d['blood_group'] ?? '',
                d['religion'] ?? '',
                d['medium_of_instruction'] ?? '',
                d['community'] ?? '',
                d['mother_tongue'] ?? '',
                d['emergency_contact_name'] ?? '',
                d['emergency_contact_phone'] ?? '',
                (d['status'] as String? ?? 'active').replaceAll('_', ' '),
              ];
            }(),
        ],
      ),
      ExportSheet(
        name: 'Attendance Summary',
        headers: ['Student', 'Class', ...AttendanceSummary.exportHeaders()],
        rows: [
          for (final s in students)
            [s['full_name'], classLabelOf(s['id'] as String), ...attSummaries[s['id']]!.exportCells()],
        ],
      ),
      ExportSheet(
        name: 'Fees Summary',
        headers: const ['Student', 'Class', 'Paid (₹)', 'Pending (₹)', 'Waived (₹)'],
        rows: [
          for (final s in students)
            () {
              final t = feeTotalsOf(s['id'] as String);
              return [
                s['full_name'],
                classLabelOf(s['id'] as String),
                _rupees(t['paid']!),
                _rupees(t['pending']!),
                _rupees(t['waived']!),
              ];
            }(),
        ],
      ),
      ExportSheet(
        name: 'Grades Summary',
        headers: const ['Student', 'Class', 'Subject', 'Average %', 'Exams counted'],
        rows: [
          for (final s in students)
            for (final entry in gradesBySubject(s['id'] as String).entries)
              [
                s['full_name'],
                classLabelOf(s['id'] as String),
                entry.key,
                double.parse(entry.value.$1.toStringAsFixed(1)),
                entry.value.$2,
              ],
        ],
      ),
    ];
  }

  Future<void> export(String fileBaseName) =>
      ExcelExportService.exportWorkbook(fileBaseName: '${fileBaseName}_${range.slug}', sheets: toSheets());
}
