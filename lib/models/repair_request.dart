import 'package:equatable/equatable.dart';

enum RepairStatus { reported, approved, inProgress, completed, cancelled }

RepairStatus repairStatusFromJson(String value) {
  switch (value) {
    case 'approved':
      return RepairStatus.approved;
    case 'in_progress':
      return RepairStatus.inProgress;
    case 'completed':
      return RepairStatus.completed;
    case 'cancelled':
      return RepairStatus.cancelled;
    default:
      return RepairStatus.reported;
  }
}

String repairStatusToJson(RepairStatus status) {
  switch (status) {
    case RepairStatus.approved:
      return 'approved';
    case RepairStatus.inProgress:
      return 'in_progress';
    case RepairStatus.completed:
      return 'completed';
    case RepairStatus.cancelled:
      return 'cancelled';
    case RepairStatus.reported:
      return 'reported';
  }
}

String repairStatusLabel(RepairStatus status) {
  switch (status) {
    case RepairStatus.reported:
      return 'Reported';
    case RepairStatus.approved:
      return 'Approved';
    case RepairStatus.inProgress:
      return 'In Progress';
    case RepairStatus.completed:
      return 'Completed';
    case RepairStatus.cancelled:
      return 'Cancelled';
  }
}

class RepairRequest extends Equatable {
  const RepairRequest({
    required this.id,
    required this.location,
    required this.category,
    required this.description,
    required this.reportedDate,
    this.responsiblePerson,
    this.estimatedCostPaise,
    this.actualCostPaise,
    this.advancePaidPaise,
    this.quotationUrl,
    this.billUrl,
    this.beforePhotoUrl,
    this.afterPhotoUrl,
    this.status = RepairStatus.reported,
    this.completionDate,
    this.remarks,
  });

  final String id;
  final String location;
  final String category;
  final String description;
  final DateTime reportedDate;
  final String? responsiblePerson;
  final int? estimatedCostPaise;
  final int? actualCostPaise;
  final int? advancePaidPaise;
  final String? quotationUrl;
  final String? billUrl;
  final String? beforePhotoUrl;
  final String? afterPhotoUrl;
  final RepairStatus status;
  final DateTime? completionDate;
  final String? remarks;

  /// Remaining payment is derived, not stored — actual cost minus advance
  /// paid, or null until an actual cost is recorded.
  int? get remainingPaise =>
      actualCostPaise == null ? null : actualCostPaise! - (advancePaidPaise ?? 0);

  factory RepairRequest.fromJson(Map<String, dynamic> json) => RepairRequest(
        id: json['id'] as String,
        location: json['location'] as String,
        category: json['category'] as String,
        description: json['description'] as String,
        reportedDate: DateTime.parse(json['reported_date'] as String),
        responsiblePerson: json['responsible_person'] as String?,
        estimatedCostPaise: json['estimated_cost_paise'] as int?,
        actualCostPaise: json['actual_cost_paise'] as int?,
        advancePaidPaise: json['advance_paid_paise'] as int?,
        quotationUrl: json['quotation_url'] as String?,
        billUrl: json['bill_url'] as String?,
        beforePhotoUrl: json['before_photo_url'] as String?,
        afterPhotoUrl: json['after_photo_url'] as String?,
        status: repairStatusFromJson(json['status'] as String),
        completionDate: json['completion_date'] != null
            ? DateTime.parse(json['completion_date'] as String)
            : null,
        remarks: json['remarks'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'location': location,
        'category': category,
        'description': description,
        'reported_date': reportedDate.toIso8601String().substring(0, 10),
        'responsible_person': responsiblePerson,
        'estimated_cost_paise': estimatedCostPaise,
        'actual_cost_paise': actualCostPaise,
        'advance_paid_paise': advancePaidPaise,
        'quotation_url': quotationUrl,
        'bill_url': billUrl,
        'before_photo_url': beforePhotoUrl,
        'after_photo_url': afterPhotoUrl,
        'status': repairStatusToJson(status),
        'completion_date': completionDate?.toIso8601String().substring(0, 10),
        'remarks': remarks,
      };

  @override
  List<Object?> get props => [id, status];
}
