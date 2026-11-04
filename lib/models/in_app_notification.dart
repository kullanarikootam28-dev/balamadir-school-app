import 'package:equatable/equatable.dart';

class InAppNotification extends Equatable {
  const InAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.relatedId,
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final String type; // 'low_attendance' | 'noticeboard' | 'general'
  final DateTime createdAt;
  final String? relatedId;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory InAppNotification.fromJson(Map<String, dynamic> json) => InAppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        type: json['type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        relatedId: json['related_id'] as String?,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      );

  @override
  List<Object?> get props => [id, readAt];
}
