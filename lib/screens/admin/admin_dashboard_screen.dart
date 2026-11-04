import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/providers/profile_provider.dart';
import 'package:school_management_app/widgets/role_scaffold.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final theme = Theme.of(context);

    return RoleScaffold(
      title: 'Admin Dashboard',
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
                      child: Icon(Icons.admin_panel_settings,
                          color: theme.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back 👋', style: theme.textTheme.bodySmall),
                        Text(
                          profileAsync.valueOrNull?.fullName ?? 'Administrator',
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
            _sectionHeader(theme, 'People'),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.people_alt_rounded,
                  label: 'User Management',
                  color: Colors.indigo,
                  onTap: () => context.push('/admin/users'),
                ),
                DashboardOptionCard(
                  icon: Icons.family_restroom_rounded,
                  label: 'Student Records',
                  color: Colors.cyan,
                  onTap: () => context.push('/admin/student-records'),
                ),
                DashboardOptionCard(
                  icon: Icons.link_rounded,
                  label: 'Link Siblings',
                  color: Colors.pinkAccent,
                  onTap: () => context.push('/admin/families'),
                ),
                DashboardOptionCard(
                  icon: Icons.badge_rounded,
                  label: 'Non-Teaching Staff',
                  color: Colors.brown,
                  onTap: () => context.push('/admin/staff'),
                ),
                DashboardOptionCard(
                  icon: Icons.school_rounded,
                  label: 'Teacher Records',
                  color: Colors.indigoAccent,
                  onTap: () => context.push('/admin/teacher-records'),
                ),
                DashboardOptionCard(
                  icon: Icons.event_available_rounded,
                  label: 'Teacher Attendance',
                  color: Colors.lightBlue,
                  onTap: () => context.push('/admin/teacher-attendance'),
                ),
                DashboardOptionCard(
                  icon: Icons.qr_code_2_rounded,
                  label: 'Daily Attendance Portal',
                  color: Colors.deepPurple,
                  onTap: () => context.push('/admin/attendance-portal'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionHeader(theme, 'Academics'),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.class_rounded,
                  label: 'Class Configuration',
                  color: Colors.teal,
                  onTap: () => context.push('/admin/classes'),
                ),
                DashboardOptionCard(
                  icon: Icons.schedule_rounded,
                  label: 'Timetable Setup',
                  color: Colors.deepOrange,
                  onTap: () => context.push('/admin/timetable'),
                ),
                DashboardOptionCard(
                  icon: Icons.event_note_rounded,
                  label: 'Academic Years',
                  color: Colors.indigoAccent,
                  onTap: () => context.push('/admin/academic-years'),
                ),
                DashboardOptionCard(
                  icon: Icons.fact_check_rounded,
                  label: 'Exam Management',
                  color: Colors.pinkAccent,
                  onTap: () => context.push('/admin/exams'),
                ),
                DashboardOptionCard(
                  icon: Icons.move_up_rounded,
                  label: 'Promote Students',
                  color: Colors.lime,
                  onTap: () => context.push('/admin/promotion'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionHeader(theme, 'Operations'),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.campaign_rounded,
                  label: 'Global Broadcasts',
                  color: Colors.purple,
                  onTap: () => context.push('/admin/broadcasts'),
                ),
                DashboardOptionCard(
                  icon: Icons.upload_file_rounded,
                  label: 'Spreadsheet Import',
                  color: Colors.brown,
                  onTap: () => context.push('/admin/import'),
                ),
                DashboardOptionCard(
                  icon: Icons.payments_rounded,
                  label: 'Fee Management',
                  color: Colors.green,
                  onTap: () => context.push('/admin/fees'),
                ),
                DashboardOptionCard(
                  icon: Icons.directions_bus_rounded,
                  label: 'Transport',
                  color: Colors.orange,
                  onTap: () => context.push('/admin/transport'),
                ),
                DashboardOptionCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'School Calendar',
                  color: Colors.deepPurpleAccent,
                  onTap: () => context.push('/admin/calendar'),
                ),
                DashboardOptionCard(
                  icon: Icons.report_outlined,
                  label: 'Complaint Reports',
                  color: Colors.redAccent,
                  onTap: () => context.push('/admin/complaints'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionHeader(theme, 'Finance'),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Expense Dashboard',
                  color: Colors.green,
                  onTap: () => context.push('/admin/expenses'),
                ),
                DashboardOptionCard(
                  icon: Icons.build_circle_rounded,
                  label: 'Repair & Maintenance',
                  color: Colors.deepOrange,
                  onTap: () => context.push('/admin/repairs'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _sectionHeader(theme, 'Insights'),
            const SizedBox(height: 12),
            DashboardOptionsGrid(
              children: [
                DashboardOptionCard(
                  icon: Icons.bar_chart_rounded,
                  label: 'Student Attendance Reports',
                  color: Colors.blue,
                  onTap: () => context.push('/admin/attendance-reports'),
                ),
                DashboardOptionCard(
                  icon: Icons.fact_check_rounded,
                  label: 'Teacher Attendance Reports',
                  color: Colors.indigo,
                  onTap: () => context.push('/admin/teacher-attendance-reports'),
                ),
                DashboardOptionCard(
                  icon: Icons.assessment_rounded,
                  label: 'Marks Reports',
                  color: Colors.deepPurple,
                  onTap: () => context.push('/admin/marks-reports'),
                ),
                DashboardOptionCard(
                  icon: Icons.emoji_events_rounded,
                  label: 'Rankings',
                  color: Colors.amber,
                  onTap: () => context.push('/admin/rankings'),
                ),
                DashboardOptionCard(
                  icon: Icons.insights_rounded,
                  label: 'Analytics',
                  color: Colors.teal,
                  onTap: () => context.push('/admin/analytics'),
                ),
                DashboardOptionCard(
                  icon: Icons.search_rounded,
                  label: 'Global Search',
                  color: Colors.blueGrey,
                  onTap: () => context.push('/admin/search'),
                ),
                DashboardOptionCard(
                  icon: Icons.history_edu_rounded,
                  label: 'Audit Log',
                  color: Colors.grey,
                  onTap: () => context.push('/admin/audit-log'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) => Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      );
}
