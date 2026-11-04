import 'package:school_management_app/main.dart';

/// Small key/value config store (`app_settings`) for the few app-wide
/// numbers an admin should be able to tune without a code change — today
/// just the expense-approval threshold.
class AppSettingsService {
  AppSettingsService._();

  static Future<int> getInt(String key, int defaultValue) async {
    final row = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', key)
        .maybeSingle();
    if (row == null) return defaultValue;
    return int.tryParse(row['value'] as String) ?? defaultValue;
  }

  static Future<void> setInt(String key, int value) async {
    await supabase.from('app_settings').upsert({'key': key, 'value': value.toString()});
  }

  static Future<int> expenseApprovalThresholdPaise() =>
      getInt('expense_approval_threshold_paise', 500000);
}
