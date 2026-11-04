import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';

/// Admin-only account management. Every call goes through a database
/// function (supabase/migrations/026_user_admin_and_multi_role.sql) that
/// checks the caller is an admin itself, so none of this needs the
/// `service_role` key in the app — and public sign-ups can stay switched
/// off (anyone holding the app's public key could otherwise create an
/// account).
class AdminUserService {
  AdminUserService._();

  /// Creates a confirmed login + profile. Returns the new user's id.
  static Future<String> registerUser({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
    String? phone,
    bool adminAccess = false,
  }) async {
    final id = await supabase.rpc('admin_create_user', params: {
      'p_email': email.trim(),
      'p_password': password,
      'p_full_name': fullName.trim(),
      'p_role': role.name,
      'p_phone': phone,
      'p_admin_access': role == UserRole.teacher && adminAccess,
    });
    return id as String;
  }

  /// Name, phone, role and (for teachers) admin access.
  static Future<void> updateUser({
    required String userId,
    required String fullName,
    String? phone,
    required UserRole role,
    bool adminAccess = false,
  }) =>
      supabase.rpc('admin_update_user', params: {
        'p_user_id': userId,
        'p_full_name': fullName.trim(),
        'p_phone': phone,
        'p_role': role.name,
        'p_admin_access': role == UserRole.teacher && adminAccess,
      });

  /// Sets a new password and signs that user out of their other devices.
  static Future<void> setPassword({required String userId, required String password}) =>
      supabase.rpc('admin_set_password', params: {
        'p_user_id': userId,
        'p_password': password,
      });

  /// Permanently deletes the login, the profile, and that person's own
  /// records (attendance, marks, fees, enrollment...).
  static Future<void> deleteUser(String userId) =>
      supabase.rpc('admin_delete_user', params: {'p_user_id': userId});
}
