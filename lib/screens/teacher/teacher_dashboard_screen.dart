import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/providers/profile_provider.dart';
import 'package:school_management_app/widgets/role_scaffold.dart';

class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final theme = Theme.of(context);

    return RoleScaffold(
      title: 'Teacher Dashboard',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.school,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back 👋', style: theme.textTheme.bodySmall),
                        Text(
                          profileAsync.valueOrNull?.fullName ?? 'Teacher',
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
            Text('Teacher Panel',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.checklist_rounded,
                  label: 'Attendance Registry',
                  color: Colors.green,
                  onTap: () => context.push('/teacher/attendance'),
                ),
                DashboardOptionCard(
                  icon: Icons.grid_on_rounded,
                  label: 'Gradebook Input',
                  color: Colors.orange,
                  onTap: () => context.push('/teacher/gradebook'),
                ),
                DashboardOptionCard(
                  icon: Icons.announcement_rounded,
                  label: 'Class Noticeboard',
                  color: Colors.blue,
                  onTap: () => context.push('/teacher/noticeboard'),
                ),
                DashboardOptionCard(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Messaging Portal',
                  color: Colors.pink,
                  onTap: () => context.push('/teacher/messages'),
                ),
                DashboardOptionCard(
                  icon: Icons.groups_rounded,
                  label: 'My Students',
                  color: Colors.teal,
                  onTap: () => context.push('/teacher/my-students'),
                ),
                DashboardOptionCard(
                  icon: Icons.event_available_outlined,
                  label: 'My Attendance History',
                  color: Colors.indigo,
                  onTap: () => context.push('/teacher/attendance-history'),
                ),
                DashboardOptionCard(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Scan Attendance QR',
                  color: Colors.deepPurple,
                  onTap: () => context.push('/teacher/qr-checkin'),
                ),
                DashboardOptionCard(
                  icon: Icons.schedule_rounded,
                  label: 'My Timetable',
                  color: Colors.deepOrange,
                  onTap: () => context.push('/teacher/timetable'),
                ),
                DashboardOptionCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'School Calendar',
                  color: Colors.brown,
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
