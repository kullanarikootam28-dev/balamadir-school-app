import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/auth_provider.dart';
import 'package:school_management_app/providers/notification_provider.dart';
import 'package:school_management_app/providers/profile_provider.dart';

/// Shared Scaffold + AppBar + sign-out action used by every role dashboard,
/// so the logout logic (and now the notification bell) lives in exactly one
/// place and every role gets it for free.
class RoleScaffold extends ConsumerWidget {
  const RoleScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final activePanel = ref.watch(activePanelProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...?actions,
          // Teacher + admin accounts: jump between the two panels.
          if (profile != null && profile.canSwitchPanels)
            IconButton(
              icon: Icon(activePanel == UserRole.admin
                  ? Icons.school_outlined
                  : Icons.admin_panel_settings_outlined),
              tooltip: activePanel == UserRole.admin
                  ? 'Switch to Teacher panel'
                  : 'Switch to Admin panel',
              onPressed: () {
                ref.read(activePanelProvider.notifier).state =
                    activePanel == UserRole.admin ? UserRole.teacher : UserRole.admin;
                context.go('/');
              },
            ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () async {
                  await context.push('/notifications');
                  ref.invalidate(unreadNotificationCountProvider);
                },
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.password_rounded),
            tooltip: 'Change password',
            onPressed: () => context.push('/change-password'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await supabase.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: body,
    );
  }
}

/// A single tappable card used in every dashboard's options grid.
class DashboardOptionCard extends StatelessWidget {
  const DashboardOptionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared grid layout for a dashboard's list of feature cards. Column count
/// adapts to available width so a desktop window (Windows build / web build)
/// shows several cards per row instead of the phone's fixed 2 columns
/// leaving most of the screen empty.
class DashboardOptionsGrid extends StatelessWidget {
  const DashboardOptionsGrid({super.key, required this.children});

  final List<Widget> children;

  int _columnsFor(double width) {
    if (width < 700) return 2;
    if (width < 1100) return 4;
    if (width < 1500) return 5;
    return 6;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.count(
          crossAxisCount: _columnsFor(constraints.maxWidth),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: children,
        );
      },
    );
  }
}
