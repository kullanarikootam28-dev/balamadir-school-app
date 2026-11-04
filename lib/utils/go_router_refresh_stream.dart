import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a Stream into a [Listenable] so GoRouter's `refreshListenable`
/// can react to it — used to re-run the `redirect` callback on every auth
/// state change (sign in / sign out / token refresh) instead of relying on
/// a manually-timed `context.go()` call racing against widget rebuilds.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
