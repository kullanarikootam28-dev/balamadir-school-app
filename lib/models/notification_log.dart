import 'package:equatable/equatable.dart';

enum NotificationTrigger { feeReminder, feePayment, attendance, marksPublished, event }

class NotificationLogEntry extends Equatable {
  const NotificationLogEntry({
    required this.id,
    required this.triggerType,
    required this.channel,
    required this.message,
    this.studentId,
    this.sentBy,
    this.sentAt,
  });

  final String id;
  final NotificationTrigger triggerType;
  final String channel;
  final String message;
  final String? studentId;
  final String? sentBy;
  final DateTime? sentAt;

  static NotificationTrigger _triggerFromJson(String value) {
    switch (value) {
      case 'fee_reminder':
        return NotificationTrigger.feeReminder;
      case 'fee_payment':
        return NotificationTrigger.feePayment;
      case 'attendance':
        return NotificationTrigger.attendance;
      case 'marks_published':
        return NotificationTrigger.marksPublished;
      default:
        return NotificationTrigger.event;
    }
  }

  static String triggerToJson(NotificationTrigger trigger) {
    switch (trigger) {
      case NotificationTrigger.feeReminder:
        return 'fee_reminder';
      case NotificationTrigger.feePayment:
        return 'fee_payment';
      case NotificationTrigger.attendance:
        return 'attendance';
      case NotificationTrigger.marksPublished:
        return 'marks_published';
      case NotificationTrigger.event:
        return 'event';
    }
  }

  factory NotificationLogEntry.fromJson(Map<String, dynamic> json) => NotificationLogEntry(
        id: json['id'] as String,
        triggerType: _triggerFromJson(json['trigger_type'] as String),
        channel: json['channel'] as String,
        message: json['message'] as String,
        studentId: json['student_id'] as String?,
        sentBy: json['sent_by'] as String?,
        sentAt: json['sent_at'] != null ? DateTime.parse(json['sent_at'] as String) : null,
      );

  @override
  List<Object?> get props => [id, triggerType, studentId];
}
