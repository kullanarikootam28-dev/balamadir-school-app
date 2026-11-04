import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/auth_provider.dart';

/// The signed-in user's `profiles` row — this is what determines which
/// role dashboard (admin/teacher/student) they see. Re-fetches when a
/// different user signs in or out (not on every token refresh).
final currentProfileProvider = FutureProvider<Profile>((ref) async {
  // Before the auth stream's first event, fall back to the restored session
  // so startup doesn't fetch twice.
  ref.watch(currentUserIdProvider
      .select((v) => v.valueOrNull ?? supabase.auth.currentUser?.id));

  final user = supabase.auth.currentUser;
  if (user == null) {
    throw StateError('No signed-in user');
  }

  final data = await supabase
      .from(SupabaseConfig.profilesTable)
      .select()
      .eq('id', user.id)
      .single();

  return Profile.fromJson(data);
});
