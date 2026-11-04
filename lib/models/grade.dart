import 'package:equatable/equatable.dart';

class Grade extends Equatable {
  const Grade({
    required this.id,
    required this.studentId,
    required this.classId,
    required this.subjectName,
    required this.score,
    required this.maxScore,
    this.examType,
    this.examId,
    this.gradedAt,
  });

  final String id;
  final String studentId;    // FK → profiles.id
  final String classId;      // FK → classes.id
  final String subjectName;  // e.g. "Mathematics"
  final double score;
  final double maxScore;
  final String? examType;    // e.g. "Midterm", "Final", "Quiz" (legacy free text)
  final String? examId;      // FK → exams.id (formal exam entity, may be null for legacy rows)
  final DateTime? gradedAt;

  double get percentage => (score / maxScore) * 100;

  String get letterGrade {
    final p = percentage;
    if (p >= 90) return 'A+';
    if (p >= 80) return 'A';
    if (p >= 70) return 'B';
    if (p >= 60) return 'C';
    if (p >= 50) return 'D';
    return 'F';
  }

  factory Grade.fromJson(Map<String, dynamic> json) => Grade(
        id: json['id'] as String,
        studentId: json['student_id'] as String,
        classId: json['class_id'] as String,
        subjectName: json['subject_name'] as String,
        score: (json['score'] as num).toDouble(),
        maxScore: (json['max_score'] as num).toDouble(),
        examType: json['exam_type'] as String?,
        examId: json['exam_id'] as String?,
        gradedAt: json['graded_at'] != null
            ? DateTime.parse(json['graded_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'student_id': studentId,
        'class_id': classId,
        'subject_name': subjectName,
        'score': score,
        'max_score': maxScore,
        'exam_type': examType,
        'exam_id': examId,
      };

  @override
  List<Object?> get props => [id, studentId, classId, subjectName];
}
