import 'package:equatable/equatable.dart';

class Exam extends Equatable {
  const Exam({
    required this.id,
    required this.name,
    required this.academicYear,
    this.examDate,
    this.createdBy,
  });

  final String id;
  final String name; // 'Test 1', 'Quarterly', 'Half Yearly', 'Annual', ...
  final String academicYear;
  final DateTime? examDate;
  final String? createdBy;

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
        id: json['id'] as String,
        name: json['name'] as String,
        academicYear: json['academic_year'] as String,
        examDate: json['exam_date'] != null
            ? DateTime.parse(json['exam_date'] as String)
            : null,
        createdBy: json['created_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'academic_year': academicYear,
        'exam_date': examDate?.toIso8601String().substring(0, 10),
        'created_by': createdBy,
      };

  @override
  List<Object?> get props => [id, name, academicYear];
}
