import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:school_management_app/main.dart';

/// Unread count for the bell icon in RoleScaffold — re-fetched whenever a
/// screen calls `ref.invalidate(unreadNotificationCountProvider)` (done by
/// notifications_screen.dart after marking things read).
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) return 0;
  final data = await supabase
      .from('in_app_notifications')
      .select('id')
      .eq('user_id', user.id)
      .isFilter('read_at', null);
  return (data as List).length;
});
