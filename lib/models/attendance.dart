import 'package:equatable/equatable.dart';

enum AttendanceStatus { present, absent, late, excused, halfDay }

extension AttendanceStatusDb on AttendanceStatus {
  /// The Postgres enum uses `half_day` (snake_case); every other value
  /// already matches its Dart name.
  String get dbValue => this == AttendanceStatus.halfDay ? 'half_day' : name;

  static AttendanceStatus fromDb(String value) => value == 'half_day'
      ? AttendanceStatus.halfDay
      : AttendanceStatus.values.firstWhere((s) => s.name == value);
}

class Attendance extends Equatable {
  const Attendance({
    required this.id,
    required this.studentId,
    required this.classId,
    required this.date,
    required this.status,
    this.markedByTeacherId,
    this.remarks,
  });

  final String id;
  final String studentId;        // FK → profiles.id
  final String classId;          // FK → classes.id
  final DateTime date;
  final AttendanceStatus status;
  final String? markedByTeacherId;
  final String? remarks;

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
        id: json['id'] as String,
        studentId: json['student_id'] as String,
        classId: json['class_id'] as String,
        date: DateTime.parse(json['date'] as String),
        status: AttendanceStatusDb.fromDb(json['status'] as String),
        markedByTeacherId: json['marked_by_teacher_id'] as String?,
        remarks: json['remarks'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'student_id': studentId,
        'class_id': classId,
        'date': date.toIso8601String().substring(0, 10),
        'status': status.dbValue,
        'marked_by_teacher_id': markedByTeacherId,
        'remarks': remarks,
      };

  @override
  List<Object?> get props => [id, studentId, classId, date, status];
}
