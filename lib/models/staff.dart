import 'package:equatable/equatable.dart';

enum StaffStatus { active, onLeave, resigned }

class NonTeachingStaff extends Equatable {
  const NonTeachingStaff({
    required this.id,
    required this.fullName,
    required this.designation,
    this.department,
    this.phone,
    this.salaryPaise,
    this.joiningDate,
    this.status = StaffStatus.active,
    this.remarks,
  });

  final String id;
  final String fullName;
  final String designation;
  final String? department;
  final String? phone;
  final int? salaryPaise;
  final DateTime? joiningDate;
  final StaffStatus status;
  final String? remarks;

  String get salaryDisplay =>
      salaryPaise == null ? '—' : '₹${(salaryPaise! / 100).toStringAsFixed(2)}';

  static StaffStatus _statusFromJson(String? value) {
    switch (value) {
      case 'on_leave':
        return StaffStatus.onLeave;
      case 'resigned':
        return StaffStatus.resigned;
      default:
        return StaffStatus.active;
    }
  }

  static String _statusToJson(StaffStatus status) {
    switch (status) {
      case StaffStatus.onLeave:
        return 'on_leave';
      case StaffStatus.resigned:
        return 'resigned';
      case StaffStatus.active:
        return 'active';
    }
  }

  factory NonTeachingStaff.fromJson(Map<String, dynamic> json) => NonTeachingStaff(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        designation: json['designation'] as String,
        department: json['department'] as String?,
        phone: json['phone'] as String?,
        salaryPaise: json['salary_paise'] as int?,
        joiningDate: json['joining_date'] != null
            ? DateTime.parse(json['joining_date'] as String)
            : null,
        status: _statusFromJson(json['status'] as String?),
        remarks: json['remarks'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'designation': designation,
        'department': department,
        'phone': phone,
        'salary_paise': salaryPaise,
        'joining_date': joiningDate?.toIso8601String().substring(0, 10),
        'status': _statusToJson(status),
        'remarks': remarks,
      };

  @override
  List<Object?> get props => [id, fullName, designation, status];
}
