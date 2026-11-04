import 'package:equatable/equatable.dart';

class AuditLogEntry extends Equatable {
  const AuditLogEntry({
    required this.id,
    required this.module,
    required this.action,
    required this.createdAt,
    this.actorId,
    this.actorRole,
    this.oldValue,
    this.newValue,
  });

  final String id;
  final String module;
  final String action;
  final DateTime createdAt;
  final String? actorId;
  final String? actorRole;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String,
        module: json['module'] as String,
        action: json['action'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        actorId: json['actor_id'] as String?,
        actorRole: json['actor_role'] as String?,
        oldValue: json['old_value'] as Map<String, dynamic>?,
        newValue: json['new_value'] as Map<String, dynamic>?,
      );

  @override
  List<Object?> get props => [id, module, action, createdAt];
}
