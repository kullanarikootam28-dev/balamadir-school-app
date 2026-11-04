import 'package:equatable/equatable.dart';

enum StudentStatus { active, transferred, archived }

/// Parent/guardian and demographic details, grounded in the school's real
/// EMIS export (EMIS Id, Admission Number, Father/Mother/Guardian
/// Name+Occupation+Education, Aadhaar, Address, Pin code, Blood Group,
/// Religion, Medium of Instruction, Community, Mother Tongue).
class StudentDetails extends Equatable {
  const StudentDetails({
    required this.studentId,
    this.emisId,
    this.admissionNumber,
    this.fatherName,
    this.fatherOccupation,
    this.fatherEducation,
    this.motherName,
    this.motherOccupation,
    this.motherEducation,
    this.guardianName,
    this.guardianOccupation,
    this.aadhaarNumber,
    this.dateOfBirth,
    this.gender,
    this.dateOfJoining,
    this.address,
    this.pinCode,
    this.bloodGroup,
    this.religion,
    this.mediumOfInstruction,
    this.community,
    this.motherTongue,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.status = StudentStatus.active,
    this.photoUrl,
    this.birthCertificateUrl,
    this.aadhaarDocUrl,
    this.tcUrl,
  });

  final String studentId; // FK → profiles.id
  final String? emisId;
  final String? admissionNumber;
  final String? fatherName;
  final String? fatherOccupation;
  final String? fatherEducation;
  final String? motherName;
  final String? motherOccupation;
  final String? motherEducation;
  final String? guardianName;
  final String? guardianOccupation;
  final String? aadhaarNumber;
  final DateTime? dateOfBirth;
  final String? gender;
  final DateTime? dateOfJoining;
  final String? address;
  final String? pinCode;
  final String? bloodGroup;
  final String? religion;
  final String? mediumOfInstruction;
  final String? community;
  final String? motherTongue;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final StudentStatus status;
  final String? photoUrl;
  final String? birthCertificateUrl;
  final String? aadhaarDocUrl;
  final String? tcUrl;

  factory StudentDetails.fromJson(Map<String, dynamic> json) => StudentDetails(
        studentId: json['student_id'] as String,
        emisId: json['emis_id'] as String?,
        admissionNumber: json['admission_number'] as String?,
        fatherName: json['father_name'] as String?,
        fatherOccupation: json['father_occupation'] as String?,
        fatherEducation: json['father_education'] as String?,
        motherName: json['mother_name'] as String?,
        motherOccupation: json['mother_occupation'] as String?,
        motherEducation: json['mother_education'] as String?,
        guardianName: json['guardian_name'] as String?,
        guardianOccupation: json['guardian_occupation'] as String?,
        aadhaarNumber: json['aadhaar_number'] as String?,
        dateOfBirth: json['date_of_birth'] != null
            ? DateTime.parse(json['date_of_birth'] as String)
            : null,
        gender: json['gender'] as String?,
        dateOfJoining: json['date_of_joining'] != null
            ? DateTime.parse(json['date_of_joining'] as String)
            : null,
        address: json['address'] as String?,
        pinCode: json['pin_code'] as String?,
        bloodGroup: json['blood_group'] as String?,
        religion: json['religion'] as String?,
        mediumOfInstruction: json['medium_of_instruction'] as String?,
        community: json['community'] as String?,
        motherTongue: json['mother_tongue'] as String?,
        emergencyContactName: json['emergency_contact_name'] as String?,
        emergencyContactPhone: json['emergency_contact_phone'] as String?,
        status: StudentStatus.values
            .firstWhere((s) => s.name == (json['status'] ?? 'active')),
        photoUrl: json['photo_url'] as String?,
        birthCertificateUrl: json['birth_certificate_url'] as String?,
        aadhaarDocUrl: json['aadhaar_doc_url'] as String?,
        tcUrl: json['tc_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'emis_id': emisId,
        'admission_number': admissionNumber,
        'father_name': fatherName,
        'father_occupation': fatherOccupation,
        'father_education': fatherEducation,
        'mother_name': motherName,
        'mother_occupation': motherOccupation,
        'mother_education': motherEducation,
        'guardian_name': guardianName,
        'guardian_occupation': guardianOccupation,
        'aadhaar_number': aadhaarNumber,
        'date_of_birth': dateOfBirth?.toIso8601String().substring(0, 10),
        'gender': gender,
        'date_of_joining': dateOfJoining?.toIso8601String().substring(0, 10),
        'address': address,
        'pin_code': pinCode,
        'blood_group': bloodGroup,
        'religion': religion,
        'medium_of_instruction': mediumOfInstruction,
        'community': community,
        'mother_tongue': motherTongue,
        'emergency_contact_name': emergencyContactName,
        'emergency_contact_phone': emergencyContactPhone,
        'status': status.name,
        'photo_url': photoUrl,
        'birth_certificate_url': birthCertificateUrl,
        'aadhaar_doc_url': aadhaarDocUrl,
        'tc_url': tcUrl,
      };

  @override
  List<Object?> get props => [studentId, status];
}
