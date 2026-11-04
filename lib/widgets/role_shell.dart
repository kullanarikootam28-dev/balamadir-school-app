import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/auth_provider.dart';
import 'package:school_management_app/providers/notification_provider.dart';
import 'package:school_management_app/providers/profile_provider.dart';
import 'package:school_management_app/widgets/app_drawer.dart';

/// One shortcut in the bottom bar.
class RoleNavItem {
  const RoleNavItem({required this.icon, required this.label, required this.route});
  final IconData icon;
  final String label;
  final String route;
}

/// The shell every dashboard sits in: hamburger → [AppDrawer], notification
/// bell, profile avatar, and a bottom bar of the role's most-used screens.
class RoleShell extends ConsumerWidget {
  const RoleShell({
    super.key,
    required this.title,
    required this.body,
    required this.navItems,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<RoleNavItem> navItems;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final activePanel = ref.watch(activePanelProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
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
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: GestureDetector(
              onTap: () => context.push(profile == null ? '/notifications' : '/profile/${profile.id}'),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage:
                    profile?.avatarUrl != null ? NetworkImage(profile!.avatarUrl!) : null,
                child: profile?.avatarUrl == null
                    ? Text(
                        (profile?.fullName.isNotEmpty ?? false)
                            ? profile!.fullName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i == 0) return; // already home
          context.push(navItems[i].route);
        },
        destinations: [
          for (final item in navItems)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}
