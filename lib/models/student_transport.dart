import 'package:equatable/equatable.dart';

class StudentTransport extends Equatable {
  const StudentTransport({
    required this.id,
    required this.studentId,
    required this.busId,
    this.stopId,
  });

  final String id;
  final String studentId;
  final String busId;
  final String? stopId;

  factory StudentTransport.fromJson(Map<String, dynamic> json) => StudentTransport(
        id: json['id'] as String,
        studentId: json['student_id'] as String,
        busId: json['bus_id'] as String,
        stopId: json['stop_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'bus_id': busId,
        'stop_id': stopId,
      };

  @override
  List<Object?> get props => [id, studentId, busId, stopId];
}
