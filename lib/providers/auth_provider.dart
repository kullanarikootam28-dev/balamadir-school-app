import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';

/// Emits every auth state change (sign in, sign out, token refresh) so
/// dependent providers can react to it.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// The signed-in user's id, changing only on sign-in / sign-out / account
/// switch — not on the hourly token refresh. Watching this instead of
/// [authStateChangesProvider] keeps a token refresh from reloading the
/// profile (which itself makes a request, which on a PC whose clock is
/// wrong triggers another refresh — the loop behind "logs in, then
/// silently drops back to the login screen").
final currentUserIdProvider = StreamProvider<String?>((ref) {
  return supabase.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
});

/// For a teacher who also has admin access: which panel they chose this
/// session. Null until they pick one (the panel chooser shows); resets
/// whenever a different account signs in.
final activePanelProvider = StateProvider<UserRole?>((ref) {
  ref.watch(currentUserIdProvider.select((v) => v.valueOrNull));
  return null;
});
