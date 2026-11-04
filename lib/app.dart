import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/auth_provider.dart';
import 'package:school_management_app/providers/profile_provider.dart';
import 'package:school_management_app/screens/auth/panel_chooser_screen.dart';
import 'package:school_management_app/screens/auth/forgot_password_screen.dart';
import 'package:school_management_app/screens/auth/login_screen.dart';
import 'package:school_management_app/screens/auth/magic_link_sign_in_screen.dart';
import 'package:school_management_app/screens/auth/set_new_password_screen.dart';
import 'package:school_management_app/screens/fees/fees_screen.dart';
import 'package:school_management_app/screens/messages/message_thread_screen.dart';
import 'package:school_management_app/screens/settings/change_password_screen.dart';
import 'package:school_management_app/screens/shared/notifications_screen.dart';
import 'package:school_management_app/screens/shared/profile_detail_screen.dart';

import 'package:school_management_app/screens/admin/academic_year_screen.dart';
import 'package:school_management_app/screens/admin/admin_dashboard_screen.dart';
import 'package:school_management_app/screens/admin/analytics_screen.dart';
import 'package:school_management_app/screens/admin/attendance_report_screen.dart';
import 'package:school_management_app/screens/admin/audit_log_screen.dart';
import 'package:school_management_app/screens/admin/class_configuration_screen.dart';
import 'package:school_management_app/screens/admin/complaint_report_screen.dart';
import 'package:school_management_app/screens/admin/daily_attendance_portal_screen.dart';
import 'package:school_management_app/screens/admin/exam_management_screen.dart';
import 'package:school_management_app/screens/admin/expense_management_screen.dart';
import 'package:school_management_app/screens/admin/family_links_screen.dart';
import 'package:school_management_app/screens/admin/fee_management_screen.dart';
import 'package:school_management_app/screens/admin/global_broadcasts_screen.dart';
import 'package:school_management_app/screens/admin/global_search_screen.dart';
import 'package:school_management_app/screens/admin/marks_report_screen.dart';
import 'package:school_management_app/screens/admin/promotion_screen.dart';
import 'package:school_management_app/screens/admin/qr_scan_log_screen.dart';
import 'package:school_management_app/screens/admin/rankings_screen.dart';
import 'package:school_management_app/screens/admin/repair_management_screen.dart';
import 'package:school_management_app/screens/admin/school_calendar_screen.dart';
import 'package:school_management_app/screens/admin/spreadsheet_import_screen.dart';
import 'package:school_management_app/screens/admin/staff_management_screen.dart';
import 'package:school_management_app/screens/admin/student_records_screen.dart';
import 'package:school_management_app/screens/admin/teacher_attendance_admin_screen.dart';
import 'package:school_management_app/screens/admin/teacher_records_screen.dart';
import 'package:school_management_app/screens/admin/timetable_setup_screen.dart';
import 'package:school_management_app/screens/admin/transport_screen.dart';
import 'package:school_management_app/screens/admin/user_management_screen.dart';

import 'package:school_management_app/screens/teacher/attendance_registry_screen.dart';
import 'package:school_management_app/screens/teacher/class_noticeboard_screen.dart';
import 'package:school_management_app/screens/teacher/gradebook_input_screen.dart';
import 'package:school_management_app/screens/teacher/messages_screen.dart';
import 'package:school_management_app/screens/teacher/my_students_screen.dart';
import 'package:school_management_app/screens/teacher/qr_checkin_screen.dart';
import 'package:school_management_app/screens/teacher/teacher_attendance_history_screen.dart';
import 'package:school_management_app/screens/teacher/teacher_dashboard_screen.dart';
import 'package:school_management_app/screens/teacher/teacher_timetable_screen.dart';

import 'package:school_management_app/screens/student/alerts_screen.dart';
import 'package:school_management_app/screens/student/attendance_calendar_screen.dart';
import 'package:school_management_app/screens/student/complaint_box_screen.dart';
import 'package:school_management_app/screens/student/profile_overview_screen.dart';
import 'package:school_management_app/screens/student/report_card_screen.dart';
import 'package:school_management_app/screens/student/student_dashboard_screen.dart';
import 'package:school_management_app/screens/student/student_messages_screen.dart';
import 'package:school_management_app/screens/student/timetable_screen.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/go_router_refresh_stream.dart';
import 'package:school_management_app/utils/password_recovery_flag.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  // A password-reset email link lands the user back in the app with a valid
  // session (see ForgotPasswordScreen), but they haven't set a new password
  // yet — this flag makes the redirect below send them to
  // SetNewPasswordScreen instead of treating it like an ordinary sign-in.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      PasswordRecoveryFlag.active = true;
    }
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable:
        GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange),
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final onAuthScreen = state.matchedLocation == '/login' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/magic-link-sign-in';
      final onSetNewPassword = state.matchedLocation == '/set-new-password';

      if (PasswordRecoveryFlag.active) {
        return onSetNewPassword ? null : '/set-new-password';
      }
      if (session == null && !onAuthScreen) return '/login';
      if (session != null && (onAuthScreen || onSetNewPassword)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (context, state) =>
              ForgotPasswordScreen(initialEmail: state.extra as String?)),
      GoRoute(
          path: '/magic-link-sign-in',
          builder: (context, state) =>
              MagicLinkSignInScreen(initialEmail: state.extra as String?)),
      GoRoute(
          path: '/set-new-password',
          builder: (_, __) => const SetNewPasswordScreen()),
      GoRoute(path: '/', builder: (_, __) => const _RoleGate()),
      GoRoute(path: '/fees', builder: (_, __) => const FeesScreen()),
      GoRoute(
          path: '/change-password',
          builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(
        path: '/messages/:peerId',
        builder: (context, state) => MessageThreadScreen(
          peerId: state.pathParameters['peerId']!,
          peerName: state.extra as String? ?? 'Chat',
        ),
      ),
      GoRoute(
        path: '/profile/:id',
        builder: (context, state) =>
            ProfileDetailScreen(profileId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),

      // ── Admin ────────────────────────────────────────────────────────────
      GoRoute(path: '/admin/users', builder: (_, __) => const UserManagementScreen()),
      GoRoute(path: '/admin/families', builder: (_, __) => const FamilyLinksScreen()),
      GoRoute(
          path: '/admin/classes',
          builder: (_, __) => const ClassConfigurationScreen()),
      GoRoute(
          path: '/admin/timetable',
          builder: (_, __) => const TimetableSetupScreen()),
      GoRoute(
          path: '/admin/broadcasts',
          builder: (_, __) => const GlobalBroadcastsScreen()),
      GoRoute(
          path: '/admin/import',
          builder: (_, __) => const SpreadsheetImportScreen()),
      GoRoute(path: '/admin/fees', builder: (_, __) => const FeeManagementScreen()),
      GoRoute(
          path: '/admin/expenses', builder: (_, __) => const ExpenseManagementScreen()),
      GoRoute(
          path: '/admin/repairs', builder: (_, __) => const RepairManagementScreen()),
      GoRoute(
          path: '/admin/attendance-reports',
          builder: (_, __) => const AttendanceReportScreen()),
      GoRoute(
          path: '/admin/marks-reports',
          builder: (_, __) => const MarksReportScreen()),
      GoRoute(path: '/admin/rankings', builder: (_, __) => const RankingsScreen()),
      GoRoute(
          path: '/admin/complaints', builder: (_, __) => const ComplaintReportScreen()),
      GoRoute(
          path: '/admin/student-records',
          builder: (_, __) => const StudentRecordsScreen()),
      GoRoute(path: '/admin/staff', builder: (_, __) => const StaffManagementScreen()),
      GoRoute(
          path: '/admin/teacher-records',
          builder: (_, __) => const TeacherRecordsScreen()),
      GoRoute(
          path: '/admin/academic-years',
          builder: (_, __) => const AcademicYearScreen()),
      GoRoute(path: '/admin/exams', builder: (_, __) => const ExamManagementScreen()),
      GoRoute(path: '/admin/promotion', builder: (_, __) => const PromotionScreen()),
      GoRoute(path: '/admin/transport', builder: (_, __) => const TransportScreen()),
      GoRoute(
          path: '/admin/calendar', builder: (_, __) => const SchoolCalendarScreen()),
      GoRoute(
          path: '/calendar',
          builder: (_, __) => const SchoolCalendarScreen(readOnly: true)),
      GoRoute(path: '/admin/search', builder: (_, __) => const GlobalSearchScreen()),
      GoRoute(path: '/admin/audit-log', builder: (_, __) => const AuditLogScreen()),
      GoRoute(path: '/admin/analytics', builder: (_, __) => const AnalyticsScreen()),
      GoRoute(
          path: '/admin/teacher-attendance',
          builder: (_, __) => const TeacherAttendanceAdminScreen()),
      GoRoute(
          path: '/admin/teacher-attendance-reports',
          builder: (_, __) => const TeacherAttendanceAdminScreen(initialTab: 1)),
      GoRoute(
          path: '/admin/attendance-portal',
          builder: (_, __) => const DailyAttendancePortalScreen()),
      GoRoute(
          path: '/admin/qr-scan-log', builder: (_, __) => const QrScanLogScreen()),

      // ── Teacher ──────────────────────────────────────────────────────────
      GoRoute(
          path: '/teacher/attendance',
          builder: (_, __) => const AttendanceRegistryScreen()),
      GoRoute(
          path: '/teacher/gradebook',
          builder: (_, __) => const GradebookInputScreen()),
      GoRoute(
          path: '/teacher/noticeboard',
          builder: (_, __) => const ClassNoticeboardScreen()),
      GoRoute(path: '/teacher/messages', builder: (_, __) => const MessagesScreen()),
      GoRoute(
          path: '/teacher/my-students', builder: (_, __) => const MyStudentsScreen()),
      GoRoute(
          path: '/teacher/attendance-history',
          builder: (_, __) => const TeacherAttendanceHistoryScreen()),
      GoRoute(
          path: '/teacher/qr-checkin', builder: (_, __) => const QrCheckinScreen()),
      GoRoute(
          path: '/teacher/timetable', builder: (_, __) => const TeacherTimetableScreen()),

      // ── Student ──────────────────────────────────────────────────────────
      GoRoute(
          path: '/student/profile',
          builder: (_, __) => const ProfileOverviewScreen()),
      GoRoute(
          path: '/student/attendance-calendar',
          builder: (_, __) => const AttendanceCalendarScreen()),
      GoRoute(
          path: '/student/report-card', builder: (_, __) => const ReportCardScreen()),
      GoRoute(
          path: '/student/timetable',
          builder: (_, __) => const StudentTimetableScreen()),
      GoRoute(path: '/student/alerts', builder: (_, __) => const AlertsScreen()),
      GoRoute(
          path: '/student/messages',
          builder: (_, __) => const StudentMessagesScreen()),
      GoRoute(
          path: '/student/complaints', builder: (_, __) => const ComplaintBoxScreen()),
    ],
  );
});

/// Shown at `/` for every signed-in user — reads their role and dispatches
/// to the correct dashboard. This is the fix for every role seeing the same
/// screen: previously nothing here ever looked at `profiles.role` at all.
class _RoleGate extends ConsumerWidget {
  const _RoleGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text("Couldn't load your account: ${friendlyErrorMessage(error)}",
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(currentProfileProvider),
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
      data: (profile) {
        // Teacher with admin access: same email, two panels — ask which one.
        if (profile.canSwitchPanels) {
          final panel = ref.watch(activePanelProvider);
          if (panel == null) return PanelChooserScreen(profile: profile);
          return panel == UserRole.admin
              ? const AdminDashboardScreen()
              : const TeacherDashboardScreen();
        }
        switch (profile.role) {
          case UserRole.admin:
            return const AdminDashboardScreen();
          case UserRole.teacher:
            return const TeacherDashboardScreen();
          case UserRole.student:
            return const StudentDashboardScreen();
        }
      },
    );
  }
}

class SchoolManagementApp extends ConsumerWidget {
  const SchoolManagementApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: 'Balamandir School App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        // TextFields have no fill by default, so with the transparent
        // scaffold background above, the logo watermark was showing
        // straight through form fields and cluttering their text (worst on
        // the login screen's Password field). A solid fill keeps every
        // field legible regardless of what's behind it.
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      // Every screen's Scaffold background is transparent (see theme above),
      // so this logo watermark shows through everywhere behind the actual
      // content — cards, lists, and forms keep their own opaque
      // backgrounds, so readability is unaffected.
      builder: (context, child) {
        return Stack(
          children: [
            Positioned.fill(
              child: Container(color: Theme.of(context).colorScheme.surface),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
            ),
            if (child != null) child,
          ],
        );
      },
      routerConfig: router,
    );
  }
}
