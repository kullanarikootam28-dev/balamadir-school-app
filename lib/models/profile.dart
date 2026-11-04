import 'package:equatable/equatable.dart';

enum UserRole { student, teacher, admin }

class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.avatarUrl,
    this.phone,
    this.createdAt,
    this.adminAccess = false,
  });

  final String id;          // Supabase Auth UUID
  final String fullName;
  final String email;
  final UserRole role;
  final String? avatarUrl;
  final String? phone;
  final DateTime? createdAt;

  /// A teacher who can also open the Admin panel (profiles.admin_access).
  final bool adminAccess;

  /// Whether this account can use the Admin panel at all.
  bool get hasAdminPanel => role == UserRole.admin || adminAccess;

  /// Teacher + admin: they pick a panel at sign-in and can switch later.
  bool get canSwitchPanels => role == UserRole.teacher && adminAccess;

  /// "TEACHER + ADMIN" for dual-role accounts, otherwise the role name.
  String get roleLabel => canSwitchPanels ? 'TEACHER + ADMIN' : role.name.toUpperCase();

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        role: UserRole.values.firstWhere((r) => r.name == json['role']),
        avatarUrl: json['avatar_url'] as String?,
        phone: json['phone'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
        adminAccess: json['admin_access'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'role': role.name,
        'avatar_url': avatarUrl,
        'phone': phone,
      };

  @override
  List<Object?> get props => [id, fullName, email, role, adminAccess];
}
