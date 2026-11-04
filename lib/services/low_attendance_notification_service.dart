import 'package:school_management_app/main.dart';
import 'package:school_management_app/screens/student/attendance_calendar_screen.dart'
    show kRequiredAttendancePercent;

/// Runs opportunistically from the student dashboard (no cron job exists in
/// this schema) — checks the signed-in student's own attendance % and, if
/// it's below the required threshold and they haven't already been told
/// this week, inserts one in_app_notifications row for themselves. Best
/// effort: never blocks or surfaces an error to the dashboard.
class LowAttendanceNotificationService {
  LowAttendanceNotificationService._();

  static Future<void> checkAndNotify(String studentId) async {
    try {
      final rows = await supabase.from('attendance').select('status').eq('student_id', studentId);
      final statuses = (rows as List).map((r) => (r as Map)['status'] as String).toList();
      if (statuses.isEmpty) return;

      final attended = statuses.fold<double>(0, (sum, s) {
        if (s == 'present' || s == 'late') return sum + 1;
        if (s == 'half_day') return sum + 0.5;
        return sum;
      });
      final percent = attended / statuses.length * 100;
      if (percent >= kRequiredAttendancePercent) return;

      final weekAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final recent = await supabase
          .from('in_app_notifications')
          .select('id')
          .eq('user_id', studentId)
          .eq('type', 'low_attendance')
          .gte('created_at', weekAgo)
          .limit(1);
      if ((recent as List).isNotEmpty) return;

      await supabase.from('in_app_notifications').insert({
        'user_id': studentId,
        'title': 'Low attendance warning',
        'body': 'Your attendance is ${percent.toStringAsFixed(1)}%, below the required '
            '${kRequiredAttendancePercent.toStringAsFixed(0)}%. Please improve your attendance.',
        'type': 'low_attendance',
      });
    } catch (_) {
      // Best-effort — never block the dashboard on this check.
    }
  }
}
