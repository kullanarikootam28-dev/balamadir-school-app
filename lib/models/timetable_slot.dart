import 'package:equatable/equatable.dart';

const List<String> kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

class TimetableSlot extends Equatable {
  const TimetableSlot({
    required this.id,
    required this.classId,
    required this.dayOfWeek,
    required this.periodNumber,
    this.startTime,
    this.endTime,
    this.subjectId,
    this.subjectName,
    this.teacherId,
    this.teacherName,
    this.className,
  });

  final String id;
  final String classId;
  final int dayOfWeek; // 1 = Monday .. 7 = Sunday
  final int periodNumber;
  final String? startTime; // "HH:mm:ss", null when no clock time is set
  final String? endTime;
  final String? subjectId;
  final String? subjectName;
  final String? teacherId;
  final String? teacherName;
  /// "Grade X – Section A", populated only when a query joins `classes` —
  /// used by a teacher's own multi-class timetable view, where each cell
  /// needs to show which class it's for instead of who teaches it.
  final String? className;

  String get dayName => kWeekdayNames[dayOfWeek - 1];

  factory TimetableSlot.fromJson(Map<String, dynamic> json) => TimetableSlot(
        id: json['id'] as String,
        classId: json['class_id'] as String,
        dayOfWeek: json['day_of_week'] as int,
        periodNumber: json['period_number'] as int,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        subjectId: json['subject_id'] as String?,
        subjectName: (json['subjects'] as Map<String, dynamic>?)?['name'] as String?,
        teacherId: json['teacher_id'] as String?,
        teacherName:
            (json['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
        className: json['classes'] != null
            ? 'Grade ${(json['classes'] as Map)['grade']} – ${(json['classes'] as Map)['section']}'
            : null,
      );

  Map<String, dynamic> toJson() => {
        'class_id': classId,
        'day_of_week': dayOfWeek,
        'period_number': periodNumber,
        'start_time': startTime,
        'end_time': endTime,
        'subject_id': subjectId,
        'teacher_id': teacherId,
      };

  @override
  List<Object?> get props => [id, classId, dayOfWeek, periodNumber];
}
