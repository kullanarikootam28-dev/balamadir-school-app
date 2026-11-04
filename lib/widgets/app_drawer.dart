import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/config/app_info.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/auth_provider.dart';
import 'package:school_management_app/providers/profile_provider.dart';

/// The current academic year, for the drawer header.
final currentAcademicYearProvider = FutureProvider<String?>((ref) async {
  try {
    final row = await supabase
        .from('academic_years')
        .select('year_label')
        .eq('is_current', true)
        .maybeSingle();
    return row?['year_label'] as String?;
  } catch (_) {
    return null;
  }
});

/// Side menu reached from the hamburger on every dashboard: who's signed in,
/// the academic year, password change, sign out, and the app version.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  String _roleLabel(Profile? profile, UserRole? activePanel) {
    if (profile == null) return '';
    if (profile.canSwitchPanels) {
      return activePanel == UserRole.admin ? 'Admin (teacher account)' : 'Teacher (also admin)';
    }
    switch (profile.role) {
      case UserRole.admin:
        return 'Administrator';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.student:
        return 'Student / Parent';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final academicYear = ref.watch(currentAcademicYearProvider).valueOrNull;
    final activePanel = ref.watch(activePanelProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                children: [
                  Image.asset('assets/images/logo.png', width: 68, height: 68),
                  const SizedBox(height: 8),
                  Text(kSchoolName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              title: Text(profile?.fullName ?? 'Signed in',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              subtitle: Text(
                [
                  _roleLabel(profile, activePanel),
                  if (academicYear != null) academicYear,
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.pop(context);
                context.push('/notifications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                context.push('/change-password');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                Navigator.pop(context);
                await supabase.auth.signOut();
                if (context.mounted) context.go('/login');
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Version $kAppVersion',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
