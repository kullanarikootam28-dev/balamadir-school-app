/// Set to true when a Supabase `AuthChangeEvent.passwordRecovery` fires (the
/// user tapped a password-reset email link), so the router's redirect logic
/// in app.dart sends them to SetNewPasswordScreen instead of home even
/// though a session now exists. Cleared once they've saved a new password.
class PasswordRecoveryFlag {
  PasswordRecoveryFlag._();
  static bool active = false;
}
r