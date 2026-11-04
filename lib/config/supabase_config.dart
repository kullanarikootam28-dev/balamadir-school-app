/// ── Supabase Project Configuration ──────────────────────────────────────────
///
/// PHASE 2 KEY INJECTION:
/// Replace the two placeholder strings below with your live credentials from:
/// https://supabase.com/dashboard → Project → Settings → API
///
/// ⚠️  NEVER commit real keys to public version control.
///     Use environment variables or a secrets manager in CI/CD.
class SupabaseConfig {
  SupabaseConfig._();

  /// Your Supabase project URL.
  /// Example: https://xyzcompany.supabase.co
  static const String projectUrl = 'https://atfyumihqsxvzzcifupg.supabase.co';

  /// Your Supabase anon/public key (safe to use client-side).
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF0Znl1bWlocXN4dnp6Y2lmdXBnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1Mzk2ODksImV4cCI6MjEwNDExNTY4OX0.Z7rfkMj9ikjmPCbZexlWHEhsbHZxZOeouonUIeoWuZg';

  /// Table names — centralised so a rename only touches this file.
  static const String profilesTable = 'profiles';
  static const String classesTable = 'classes';
  static const String attendanceTable = 'attendance';
  static const String gradesTable = 'grades';
  static const String feePaymentsTable = 'fee_payments';

  /// Realtime channels
  static const String attendanceChannel = 'realtime:attendance';
  static const String gradesChannel = 'realtime:grades';
}
