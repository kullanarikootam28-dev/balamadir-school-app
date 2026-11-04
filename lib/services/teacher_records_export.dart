import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/attendance_summary.dart';
import 'package:school_management_app/utils/fetch_all.dart';
import 'package:school_management_app/widgets/export_range_dialog.dart';

/// Everything the admin knows about a set of teachers for one period:
/// profile + employment details, attendance by category, the daily log with
/// local check-in/out times, leaves, and class/subject assignments.
/// Shared by the Teacher Records list, a single teacher's record, and the
/// Teacher Attendance Reports tab so all three export the same workbook.
class TeacherRecordsData {
  TeacherRecordsData._({
    required this.range,
    required this.teachers,
    required this.details,
    required this.attendance,
    required this.leaves,
    required this.assignments,
  });

  final ReportRange range;
  final List<Map<String, dynamic>> teachers; // id, full_name, email, phone
  final Map<String, Map<String, dynamic>> details; // teacher_id -> teacher_details row
  final List<Map<String, dynamic>> attendance; // in range, oldest first
  final List<Map<String, dynamic>> leaves; // in range, oldest first
  final Map<String, List<String>> assignments; // teacher_id -> ["Grade X – A · Maths", ...]

  String nameOf(String teacherId) =>
      teachers.firstWhere((t) => t['id'] == teacherId, orElse: () => const {'full_name': '—'})['full_name']
          as String;

  /// One summary per teacher (every teacher in [teachers], even with no
  /// marked days), including CL/LP leave counts.
  Map<String, AttendanceSummary> get summaries {
    final out = {for (final t in teachers) t['id'] as String: AttendanceSummary()};
    for (final r in attendance) {
      out[r['teacher_id']]?.addStatus(r['status'] as String);
    }
    for (final l in leaves) {
      out[l['teacher_id']]?.addLeave(l['leave_type'] as String);
    }
    return out;
  }

  static Future<TeacherRecordsData> load({required ReportRange range, Set<String>? teacherIds}) async {
    final ids = teacherIds?.toList();
    final results = await Future.wait<dynamic>([
      fetchAllRows(() {
        final q = supabase.from('profiles').select('id, full_name, email, phone').eq('role', 'teacher');
        return (ids == null ? q : q.inFilter('id', ids)).order('full_name', ascending: true).order('id');
      }),
      fetchAllRows(() {
        final q = supabase.from('teacher_details').select();
        return (ids == null ? q : q.inFilter('teacher_id', ids)).order('teacher_id');
      }),
      fetchAllRows(() {
        final q = supabase
            .from('teacher_attendance')
            .select('id, teacher_id, date, status, check_in_time, check_out_time, remarks')
            .gte('date', range.startIso)
            .lt('date', range.endIso);
        return (ids == null ? q : q.inFilter('teacher_id', ids))
            .order('date', ascending: true)
            .order('id');
      }),
      fetchAllRows(() {
        final q = supabase
            .from('teacher_leaves')
            .select('id, teacher_id, leave_date, leave_type, remarks')
            .gte('leave_date', range.startIso)
            .lt('leave_date', range.endIso);
        return (ids == null ? q : q.inFilter('teacher_id', ids))
            .order('leave_date', ascending: true)
            .order('id');
      }),
      fetchAllRows(() {
        final q = supabase
            .from('class_subject_teachers')
            .select('id, teacher_id, classes(grade, section), subjects(name)');
        return (ids == null ? q : q.inFilter('teacher_id', ids)).order('id');
      }),
      fetchAllRows(() {
        final q = supabase.from('classes').select('id, teacher_id, grade, section').not('teacher_id', 'is', null);
        return (ids == null ? q : q.inFilter('teacher_id', ids)).order('id');
      }),
    ]);

    String classLabel(Map? c) => c == null ? '—' : 'Grade ${c['grade']} – ${c['section']}';
    final assignments = <String, List<String>>{};
    for (final row in results[4] as List<Map<String, dynamic>>) {
      assignments
          .putIfAbsent(row['teacher_id'] as String, () => [])
          .add('${classLabel(row['classes'] as Map?)} · ${(row['subjects'] as Map?)?['name'] ?? '—'}');
    }
    for (final row in results[5] as List<Map<String, dynamic>>) {
      assignments.putIfAbsent(row['teacher_id'] as String, () => []).add('${classLabel(row)} · Class teacher');
    }

    return TeacherRecordsData._(
      range: range,
      teachers: results[0] as List<Map<String, dynamic>>,
      details: {
        for (final d in results[1] as List<Map<String, dynamic>>) d['teacher_id'] as String: d,
      },
      attendance: results[2] as List<Map<String, dynamic>>,
      leaves: results[3] as List<Map<String, dynamic>>,
      assignments: assignments,
    );
  }

  static String localTime(Object? iso) =>
      iso == null ? '' : DateFormat('h:mm a').format(DateTime.parse(iso as String).toLocal());

  static String _date(Object? iso) =>
      iso == null ? '' : DateFormat('dd-MM-yyyy').format(DateTime.parse(iso as String));

  List<ExportSheet> toSheets() {
    final summaries = this.summaries;
    final monthly = <String, AttendanceSummary>{}; // "teacherId|yyyy-MM"
    for (final r in attendance) {
      final month = (r['date'] as String).substring(0, 7);
      monthly.putIfAbsent('${r['teacher_id']}|$month', AttendanceSummary.new).addStatus(r['status'] as String);
    }
    for (final l in leaves) {
      final month = (l['leave_date'] as String).substring(0, 7);
      monthly.putIfAbsent('${l['teacher_id']}|$month', AttendanceSummary.new).addLeave(l['leave_type'] as String);
    }
    final monthlyKeys = monthly.keys.toList()
      ..sort((a, b) {
        final byName = nameOf(a.split('|')[0]).compareTo(nameOf(b.split('|')[0]));
        return byName != 0 ? byName : a.split('|')[1].compareTo(b.split('|')[1]);
      });

    return [
      ExportSheet(
        name: 'Teachers',
        headers: const [
          'Name', 'Email', 'Phone', 'Qualification', 'Specialization', 'Experience (yrs)',
          'Date of joining', 'Status', 'Address', 'Classes & subjects', 'Remarks',
        ],
        rows: [
          for (final t in teachers)
            () {
              final d = details[t['id']] ?? const <String, dynamic>{};
              return [
                t['full_name'],
                t['email'],
                t['phone'] ?? '',
                d['qualification'] ?? '',
                d['specialization'] ?? '',
                d['experience_years'],
                _date(d['joining_date']),
                (d['status'] as String? ?? 'active').replaceAll('_', ' '),
                d['address'] ?? '',
                (assignments[t['id']] ?? const []).join('; '),
                d['remarks'] ?? '',
              ];
            }(),
        ],
      ),
      ExportSheet(
        name: 'Attendance Summary',
        headers: ['Teacher', ...AttendanceSummary.exportHeaders(withLeaves: true)],
        rows: [
          for (final t in teachers)
            [t['full_name'], ...summaries[t['id']]!.exportCells(withLeaves: true)],
        ],
      ),
      ExportSheet(
        name: 'Monthly Summary',
        headers: ['Teacher', 'Month', ...AttendanceSummary.exportHeaders(withLeaves: true)],
        rows: [
          for (final key in monthlyKeys)
            [
              nameOf(key.split('|')[0]),
              DateFormat('MMM yyyy').format(DateTime.parse('${key.split('|')[1]}-01')),
              ...monthly[key]!.exportCells(withLeaves: true),
            ],
        ],
      ),
      ExportSheet(
        name: 'Daily Log',
        headers: const ['Date', 'Teacher', 'Status', 'Check in', 'Check out', 'Remarks'],
        rows: [
          for (final r in attendance)
            [
              _date(r['date']),
              nameOf(r['teacher_id'] as String),
              categoryLabel(r['status'] as String),
              localTime(r['check_in_time']),
              localTime(r['check_out_time']),
              r['remarks'] ?? '',
            ],
        ],
      ),
      ExportSheet(
        name: 'Leaves',
        headers: const ['Date', 'Teacher', 'Type', 'Remarks'],
        rows: [
          for (final l in leaves)
            [
              _date(l['leave_date']),
              nameOf(l['teacher_id'] as String),
              categoryLabel(l['leave_type'] as String),
              l['remarks'] ?? '',
            ],
        ],
      ),
      ExportSheet(
        name: 'Classes & Subjects',
        headers: const ['Teacher', 'Class · Subject'],
        rows: [
          for (final t in teachers)
            for (final a in assignments[t['id']] ?? const <String>[]) [t['full_name'], a],
        ],
      ),
    ];
  }

  Future<void> export(String fileBaseName) =>
      ExcelExportService.exportWorkbook(fileBaseName: '${fileBaseName}_${range.slug}', sheets: toSheets());
}
