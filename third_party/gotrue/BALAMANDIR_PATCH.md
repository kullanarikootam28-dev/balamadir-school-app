# Patched gotrue 2.27.2

This is the upstream `gotrue` 2.27.2 package (MIT, see LICENSE) with one fix,
pulled in through `dependency_overrides` in the app's pubspec.yaml.

## The problem
Upstream reads a session's expiry from the JWT `exp` claim (server time) and
compares it with `DateTime.now()` (the device's clock). On a PC whose clock or
time zone is wrong by an hour or more, every fresh token looks expired: the
app refreshes in a tight loop (30+ refreshes a minute), the server rate-limits
it, and the user is dropped back on the login screen with no error.

## The fix (search for `[BALAMANDIR PATCH]`)
- `lib/src/types/session.dart`: new `Session.fromServerJson` re-expresses the
  expiry on the device's clock (`exp + (now - iat)`, only when the difference
  is over 60 s); `toJson`/`fromJson` persist that value as `expires_at_local`.
- `lib/src/types/auth_response.dart` and `lib/src/gotrue_client.dart`: token
  responses from the server use `fromServerJson`.

Covered by `test/clock_skew_session_test.dart`.

## Upgrading supabase_flutter later
If a newer supabase_flutter needs a newer gotrue, copy the new gotrue into
this folder and re-apply the three `[BALAMANDIR PATCH]` edits (or drop the
override if upstream has fixed clock skew by then).
