import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';

/// General-purpose audit trail (module 22 of the client spec: track every
/// action, who did it, in what role, old/new value, with a timestamp).
/// Failing to write an audit entry must never block the action it's
/// describing, so every call swallows its own errors.
class AuditService {
  AuditService._();

  static String? _cachedUserId;
  static String? _cachedRole;

  static Future<String?> _currentActorRole(String userId) async {
    if (_cachedUserId == userId && _cachedRole != null) return _cachedRole;
    try {
      final row = await supabase
          .from(SupabaseConfig.profilesTable)
          .select('role')
          .eq('id', userId)
          .single();
      _cachedUserId = userId;
      _cachedRole = row['role'] as String?;
      return _cachedRole;
    } catch (_) {
      return null;
    }
  }

  static Future<void> log({
    required String module,
    required String action,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final role = await _currentActorRole(user.id);
      await supabase.from('audit_log').insert({
        'actor_id': user.id,
        'actor_role': role,
        'module': module,
        'action': action,
        'old_value': oldValue,
        'new_value': newValue,
      });
    } catch (_) {
      // Best-effort — never let audit logging break the caller's flow.
    }
  }
}
