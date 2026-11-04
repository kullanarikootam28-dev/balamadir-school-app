import 'package:equatable/equatable.dart';

enum TeacherStatus { active, onLeave, resigned }

/// Professional/employment record for a teacher — the teacher-side
/// counterpart of student_details.dart. Added in 013_fix_onboarding_submissions.sql
/// (qualification/specialization/experience/joining/status/remarks) and
/// extended in 014_teacher_documents.sql (address + document URLs).
class TeacherDetails extends Equatable {
  const TeacherDetails({
    required this.teacherId,
    this.qualification,
    this.specialization,
    this.experienceYears,
    this.joiningDate,
    this.status = TeacherStatus.active,
    this.remarks,
    this.address,
    this.resumeUrl,
    this.certificateUrl,
    this.idProofUrl,
  });

  final String teacherId;
  final String? qualification;
  final String? specialization;
  final int? experienceYears;
  final DateTime? joiningDate;
  final TeacherStatus status;
  final String? remarks;
  final String? address;
  final String? resumeUrl;
  final String? certificateUrl;
  final String? idProofUrl;

  static TeacherStatus _statusFromJson(String? value) {
    switch (value) {
      case 'on_leave':
        return TeacherStatus.onLeave;
      case 'resigned':
        return TeacherStatus.resigned;
      default:
        return TeacherStatus.active;
    }
  }

  static String statusToJson(TeacherStatus status) {
    switch (status) {
      case TeacherStatus.onLeave:
        return 'on_leave';
      case TeacherStatus.resigned:
        return 'resigned';
      case TeacherStatus.active:
        return 'active';
    }
  }

  factory TeacherDetails.fromJson(Map<String, dynamic> json) => TeacherDetails(
        teacherId: json['teacher_id'] as String,
        qualification: json['qualification'] as String?,
        specialization: json['specialization'] as String?,
        experienceYears: json['experience_years'] as int?,
        joiningDate: json['joining_date'] != null
            ? DateTime.parse(json['joining_date'] as String)
            : null,
        status: _statusFromJson(json['status'] as String?),
        remarks: json['remarks'] as String?,
        address: json['address'] as String?,
        resumeUrl: json['resume_url'] as String?,
        certificateUrl: json['certificate_url'] as String?,
        idProofUrl: json['id_proof_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'teacher_id': teacherId,
        'qualification': qualification,
        'specialization': specialization,
        'experience_years': experienceYears,
        'joining_date': joiningDate?.toIso8601String().substring(0, 10),
        'status': statusToJson(status),
        'remarks': remarks,
        'address': address,
        'resume_url': resumeUrl,
        'certificate_url': certificateUrl,
        'id_proof_url': idProofUrl,
      };

  @override
  List<Object?> get props => [teacherId, status];
}
