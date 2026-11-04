import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/import_result.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/services/admin_user_service.dart';

/// Maps a template field name (e.g. 'grade', 'teacher_email') to the column
/// index the admin picked for it in the mapping UI. Unmapped/optional fields
/// are absent or map to null.
typedef ColumnMapping = Map<String, int?>;

class ParsedSheet {
  const ParsedSheet({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

/// Parses admin-uploaded .xlsx/.csv files and bulk-writes their rows into
/// the existing classes/timetable_slots/class_students tables.
///
/// Row-level errors never abort the batch — each row is processed and
/// recorded independently, since a single typo shouldn't discard an entire
/// spreadsheet's worth of otherwise-valid data. New student rows go through
/// [AdminUserService.registerUser] (the same throwaway-client sign-up
/// pattern already used for one-at-a-time registration in User Management),
/// with an auto-generated password surfaced once in the results panel.
class SpreadsheetImportService {
  static Future<ParsedSheet> parseFile(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Could not read the selected file.');
    }
    final ext = (file.extension ?? '').toLowerCase();

    List<List<String>> table;
    if (ext == 'csv') {
      // Normalize line endings first — CsvToListConverter's eol
      // auto-detection can fail on bare \n (Unix-style) files and merge
      // every line into a single row instead of splitting them.
      final content = utf8
          .decode(bytes, allowMalformed: true)
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final parsed = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
          .convert(content);
      table = parsed.map((r) => r.map((e) => e.toString().trim()).toList()).toList();
    } else if (ext == 'xlsx') {
      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw Exception('The workbook has no sheets.');
      }
      final sheet = workbook.tables[workbook.tables.keys.first]!;
      table = sheet.rows
          .map((r) => r.map((c) => (c?.value?.toString() ?? '').trim()).toList())
          .toList();
    } else {
      throw Exception('Unsupported file type "$ext" — use .xlsx or .csv.');
    }

    table = table.where((r) => r.any((cell) => cell.isNotEmpty)).toList();
    if (table.isEmpty) {
      throw Exception('The file has no data.');
    }

    final headers = table.first;
    final rows = table.skip(1).map((r) => _pad(r, headers.length)).toList();
    return ParsedSheet(headers: headers, rows: rows);
  }

  static List<String> _pad(List<String> row, int length) {
    if (row.length >= length) return row;
    return [...row, ...List.filled(length - row.length, '')];
  }

  static String? _cell(List<String> row, ColumnMapping mapping, String field) {
    final idx = mapping[field];
    if (idx == null || idx >= row.length) return null;
    final value = row[idx].trim();
    return value.isEmpty ? null : value;
  }

  static int _parseDayOfWeek(String raw) {
    final asInt = int.tryParse(raw.trim());
    if (asInt != null && asInt >= 1 && asInt <= 7) return asInt;
    const names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final lower = raw.trim().toLowerCase();
    final idx = names.indexWhere((n) => lower.startsWith(n));
    if (idx == -1) {
      throw Exception('Could not parse day_of_week "$raw" (use 1-7 or a day name)');
    }
    return idx + 1;
  }

  static String _normalizeTime(String raw) {
    final parts = raw.trim().split(':');
    return parts.length == 2 ? '$raw:00' : raw;
  }

  static String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rand = Random.secure();
    return List.generate(10, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  static Future<String?> _lookupTeacherId(String? email) async {
    if (email == null) return null;
    final match = await supabase
        .from(SupabaseConfig.profilesTable)
        .select('id')
        .eq('email', email)
        .maybeSingle();
    final id = match?['id'] as String?;
    if (id == null) {
      throw Exception('No teacher found with email $email');
    }
    return id;
  }

  static Future<String?> _lookupClassId(
      String grade, String section, String academicYear) async {
    final match = await supabase
        .from(SupabaseConfig.classesTable)
        .select('id')
        .eq('grade', grade)
        .eq('section', section)
        .eq('academic_year', academicYear)
        .maybeSingle();
    return match?['id'] as String?;
  }

  static Future<ImportResult> importClasses(
      ParsedSheet sheet, ColumnMapping mapping) async {
    var success = 0;
    final errors = <ImportRowError>[];

    for (var i = 0; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      try {
        final grade = _cell(row, mapping, 'grade');
        final section = _cell(row, mapping, 'section');
        if (grade == null || section == null) {
          throw Exception('grade and section are required');
        }
        final academicYear =
            _cell(row, mapping, 'academic_year') ?? DateTime.now().year.toString();
        final teacherId = await _lookupTeacherId(_cell(row, mapping, 'teacher_email'));

        await supabase.from(SupabaseConfig.classesTable).upsert(
          {
            'grade': grade,
            'section': section,
            'academic_year': academicYear,
            'teacher_id': teacherId,
          },
          onConflict: 'grade,section,academic_year',
        );
        success++;
      } catch (e) {
        errors.add(ImportRowError(row: i + 1, message: e.toString()));
      }
    }
    return ImportResult(successCount: success, errors: errors);
  }

  static Future<ImportResult> importTimetable(
      ParsedSheet sheet, ColumnMapping mapping) async {
    var success = 0;
    final errors = <ImportRowError>[];

    for (var i = 0; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      try {
        final grade = _cell(row, mapping, 'grade');
        final section = _cell(row, mapping, 'section');
        if (grade == null || section == null) {
          throw Exception('grade and section are required');
        }
        final academicYear =
            _cell(row, mapping, 'academic_year') ?? DateTime.now().year.toString();
        final classId = await _lookupClassId(grade, section, academicYear);
        if (classId == null) {
          throw Exception('No class found for Grade $grade - Section $section ($academicYear)');
        }

        final dayRaw = _cell(row, mapping, 'day_of_week');
        if (dayRaw == null) throw Exception('day_of_week is required');
        final dayOfWeek = _parseDayOfWeek(dayRaw);

        final periodRaw = _cell(row, mapping, 'period_number');
        if (periodRaw == null) throw Exception('period_number is required');
        final periodNumber = int.tryParse(periodRaw);
        if (periodNumber == null) {
          throw Exception('period_number "$periodRaw" is not a number');
        }

        final subjectName = _cell(row, mapping, 'subject_name');
        String? subjectId;
        if (subjectName != null) {
          final existing = await supabase
              .from('subjects')
              .select('id')
              .eq('name', subjectName)
              .maybeSingle();
          if (existing != null) {
            subjectId = existing['id'] as String;
          } else {
            final created = await supabase
                .from('subjects')
                .insert({'name': subjectName})
                .select('id')
                .single();
            subjectId = created['id'] as String;
          }
        }

        final teacherId = await _lookupTeacherId(_cell(row, mapping, 'teacher_email'));

        final startTime = _cell(row, mapping, 'start_time');
        final endTime = _cell(row, mapping, 'end_time');
        if (startTime == null || endTime == null) {
          throw Exception('start_time and end_time are required');
        }

        await supabase.from('timetable_slots').upsert(
          {
            'class_id': classId,
            'day_of_week': dayOfWeek,
            'period_number': periodNumber,
            'subject_id': subjectId,
            'teacher_id': teacherId,
            'start_time': _normalizeTime(startTime),
            'end_time': _normalizeTime(endTime),
          },
          onConflict: 'class_id,day_of_week,period_number',
        );
        success++;
      } catch (e) {
        errors.add(ImportRowError(row: i + 1, message: e.toString()));
      }
    }
    return ImportResult(successCount: success, errors: errors);
  }

  static Future<ImportResult> importStudents(
      ParsedSheet sheet, ColumnMapping mapping) async {
    var success = 0;
    final errors = <ImportRowError>[];
    final newAccounts = <GeneratedAccount>[];

    for (var i = 0; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      try {
        final fullName = _cell(row, mapping, 'full_name');
        final email = _cell(row, mapping, 'email');
        if (fullName == null || email == null) {
          throw Exception('full_name and email are required');
        }
        final grade = _cell(row, mapping, 'grade');
        final section = _cell(row, mapping, 'section');
        if (grade == null || section == null) {
          throw Exception('grade and section are required');
        }
        final academicYear =
            _cell(row, mapping, 'academic_year') ?? DateTime.now().year.toString();
        final rollNumber = _cell(row, mapping, 'roll_number');
        final phone = _cell(row, mapping, 'phone');

        final classId = await _lookupClassId(grade, section, academicYear);
        if (classId == null) {
          throw Exception('No class found for Grade $grade - Section $section ($academicYear)');
        }

        final existingProfile = await supabase
            .from(SupabaseConfig.profilesTable)
            .select('id')
            .eq('email', email)
            .maybeSingle();

        String studentId;
        if (existingProfile != null) {
          studentId = existingProfile['id'] as String;
        } else {
          final password = _generatePassword();
          studentId = await AdminUserService.registerUser(
            email: email,
            password: password,
            fullName: fullName,
            role: UserRole.student,
            phone: phone,
          );
          newAccounts.add(GeneratedAccount(name: fullName, email: email, password: password));
        }

        // A student has one current class, so a re-import that places them
        // in a different class moves them rather than failing on the
        // one-class-per-student constraint.
        await supabase.from('class_students').upsert(
          {
            'class_id': classId,
            'student_id': studentId,
            'roll_number': rollNumber,
          },
          onConflict: 'student_id',
        );
        success++;
      } catch (e) {
        errors.add(ImportRowError(row: i + 1, message: e.toString()));
      }
    }
    return ImportResult(successCount: success, errors: errors, newAccounts: newAccounts);
  }

  /// Builds a ready-to-fill sample spreadsheet for one of the three import
  /// tabs and hands it to the OS share sheet, so an admin without a data
  /// export handy still sees exactly which columns and format are expected.
  static Future<void> shareSampleSheet({
    required String fileBaseName,
    required List<String> headers,
    required List<List<String>> sampleRows,
  }) async {
    final csv = const ListToCsvConverter().convert([headers, ...sampleRows]);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileBaseName.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$fileBaseName sample template',
      text: 'Fill in your data below the header row, then re-upload this file.',
    );
  }
}
