import 'package:equatable/equatable.dart';

class ExamSubject extends Equatable {
  const ExamSubject({
    required this.id,
    required this.examId,
    required this.subjectId,
    required this.classId,
    required this.maxMarks,
    required this.passMarks,
  });

  final String id;
  final String examId;
  final String subjectId;
  final String classId;
  final double maxMarks;
  final double passMarks;

  factory ExamSubject.fromJson(Map<String, dynamic> json) => ExamSubject(
        id: json['id'] as String,
        examId: json['exam_id'] as String,
        subjectId: json['subject_id'] as String,
        classId: json['class_id'] as String,
        maxMarks: (json['max_marks'] as num).toDouble(),
        passMarks: (json['pass_marks'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'exam_id': examId,
        'subject_id': subjectId,
        'class_id': classId,
        'max_marks': maxMarks,
        'pass_marks': passMarks,
      };

  @override
  List<Object?> get props => [id, examId, subjectId, classId];
}
