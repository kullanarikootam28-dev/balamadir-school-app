import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/providers/profile_provider.dart';
import 'package:school_management_app/services/low_attendance_notification_service.dart';
import 'package:school_management_app/widgets/announcement_slideshow.dart';
import 'package:school_management_app/widgets/child_switcher_card.dart';
import 'package:school_management_app/widgets/role_scaffold.dart';

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends ConsumerState<StudentDashboardScreen> {
  @override
  void initState() {
    super.initState();
    final studentId = supabase.auth.currentUser?.id;
    if (studentId != null) {
      LowAttendanceNotificationService.checkAndNotify(studentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final family = ref.watch(familyStudentsProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);

    return RoleScaffold(
      title: 'Student Dashboard',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One login covering several children: pick whose records to show.
            if (family.length > 1) ...[
              ChildSwitcherCard(students: family),
              const SizedBox(height: 16),
            ],
            // Notice photos, scrolling with the page like any other content.
            const AnnouncementSlideshow(),
            if (family.length <= 1)
              Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.person,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back 👋', style: theme.textTheme.bodySmall),
                        Text(
                          profileAsync.valueOrNull?.fullName ?? 'Student',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('My Panel',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.badge_rounded,
                  label: 'Profile Overview',
                  color: Colors.indigo,
                  onTap: () => context.push('/student/profile'),
                ),
                DashboardOptionCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'Attendance Calendar',
                  color: Colors.green,
                  onTap: () => context.push('/student/attendance-calendar'),
                ),
                DashboardOptionCard(
                  icon: Icons.school_rounded,
                  label: 'Academic Report Card',
                  color: Colors.orange,
                  onTap: () => context.push('/student/report-card'),
                ),
                DashboardOptionCard(
                  icon: Icons.schedule_rounded,
                  label: 'Daily Timetable',
                  color: Colors.deepPurple,
                  onTap: () => context.push('/student/timetable'),
                ),
                DashboardOptionCard(
                  icon: Icons.notifications_active_rounded,
                  label: 'Alerts Dashboard',
                  color: Colors.redAccent,
                  onTap: () => context.push('/student/alerts'),
                ),
                DashboardOptionCard(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Messages',
                  color: Colors.pink,
                  onTap: () => context.push('/student/messages'),
                ),
                DashboardOptionCard(
                  icon: Icons.payment_rounded,
                  label: 'Fee Payments',
                  color: Colors.purple,
                  onTap: () => context.push('/fees'),
                ),
                DashboardOptionCard(
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Complaint Box',
                  color: Colors.brown,
                  onTap: () => context.push('/student/complaints'),
                ),
                DashboardOptionCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'School Calendar',
                  color: Colors.indigo,
                  onTap: () => context.push('/calendar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
