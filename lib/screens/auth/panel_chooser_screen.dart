import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/auth_provider.dart';

/// Shown after sign-in to a teacher who also has admin access, so the same
/// email can work as either role. They can switch later from the
/// dashboard's top bar.
class PanelChooserScreen extends ConsumerWidget {
  const PanelChooserScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required UserRole panel,
    }) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref.read(activePanelProvider.notifier).state = panel,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('Welcome, ${profile.fullName}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Your account can open two panels. Which one do you need now?',
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                option(
                  icon: Icons.admin_panel_settings,
                  title: 'Admin panel',
                  subtitle: 'Users, records, reports, fees and school settings',
                  panel: UserRole.admin,
                ),
                const SizedBox(height: 12),
                option(
                  icon: Icons.school,
                  title: 'Teacher panel',
                  subtitle: 'Your classes, attendance, gradebook and noticeboard',
                  panel: UserRole.teacher,
                ),
                const SizedBox(height: 16),
                Text('You can switch any time from the top bar.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => supabase.auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
