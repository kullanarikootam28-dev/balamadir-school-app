import 'package:equatable/equatable.dart';

class AcademicYear extends Equatable {
  const AcademicYear({
    required this.id,
    required this.yearLabel,
    this.startDate,
    this.endDate,
    this.isCurrent = false,
    this.archived = false,
  });

  final String id;
  final String yearLabel;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final bool archived;

  factory AcademicYear.fromJson(Map<String, dynamic> json) => AcademicYear(
        id: json['id'] as String,
        yearLabel: json['year_label'] as String,
        startDate: json['start_date'] != null
            ? DateTime.parse(json['start_date'] as String)
            : null,
        endDate: json['end_date'] != null
            ? DateTime.parse(json['end_date'] as String)
            : null,
        isCurrent: json['is_current'] as bool? ?? false,
        archived: json['archived'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'year_label': yearLabel,
        'start_date': startDate?.toIso8601String().substring(0, 10),
        'end_date': endDate?.toIso8601String().substring(0, 10),
        'is_current': isCurrent,
        'archived': archived,
      };

  @override
  List<Object?> get props => [id, yearLabel, isCurrent, archived];
}
