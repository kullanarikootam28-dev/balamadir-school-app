import 'package:equatable/equatable.dart';

class ClassModel extends Equatable {
  const ClassModel({
    required this.id,
    required this.grade,
    required this.section,
    this.teacherId,
    this.academicYear,
  });

  final String id;
  final String grade;      // e.g. "10"
  final String section;    // e.g. "A"
  final String? teacherId; // FK → profiles.id
  final String? academicYear;

  String get displayName => 'Grade $grade – Section $section';

  factory ClassModel.fromJson(Map<String, dynamic> json) => ClassModel(
        id: json['id'] as String,
        grade: json['grade'] as String,
        section: json['section'] as String,
        teacherId: json['teacher_id'] as String?,
        academicYear: json['academic_year'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'grade': grade,
        'section': section,
        'teacher_id': teacherId,
        'academic_year': academicYear,
      };

  @override
  List<Object?> get props => [id, grade, section];
}
