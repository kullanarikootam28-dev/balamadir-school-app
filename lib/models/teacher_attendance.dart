import 'package:equatable/equatable.dart';
import 'package:school_management_app/models/attendance.dart';

class TeacherAttendance extends Equatable {
  const TeacherAttendance({
    required this.id,
    required this.teacherId,
    required this.date,
    required this.status,
    this.markedBy,
    this.remarks,
    this.checkInTime,
    this.checkOutTime,
  });

  final String id;
  final String teacherId;
  final DateTime date;
  final AttendanceStatus status;
  final String? markedBy;
  final String? remarks;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;

  factory TeacherAttendance.fromJson(Map<String, dynamic> json) => TeacherAttendance(
        id: json['id'] as String,
        teacherId: json['teacher_id'] as String,
        date: DateTime.parse(json['date'] as String),
        status: AttendanceStatusDb.fromDb(json['status'] as String),
        markedBy: json['marked_by'] as String?,
        remarks: json['remarks'] as String?,
        // .toLocal() matters here: these come back as UTC timestamptz
        // strings, and displaying them as-is (e.g. via DateFormat) shows
        // the UTC clock time, not the phone's actual local time.
        checkInTime: json['check_in_time'] != null
            ? DateTime.parse(json['check_in_time'] as String).toLocal()
            : null,
        checkOutTime: json['check_out_time'] != null
            ? DateTime.parse(json['check_out_time'] as String).toLocal()
            : null,
      );

  Map<String, dynamic> toJson() => {
        'teacher_id': teacherId,
        'date': date.toIso8601String().substring(0, 10),
        'status': status.dbValue,
        'marked_by': markedBy,
        'remarks': remarks,
      };

  @override
  List<Object?> get props => [id, teacherId, date, status];
}
