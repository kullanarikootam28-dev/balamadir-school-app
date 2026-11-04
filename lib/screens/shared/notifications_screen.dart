import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/in_app_notification.dart';
import 'package:school_management_app/providers/notification_provider.dart';
import 'package:school_management_app/utils/error_messages.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loading = true;
  List<InAppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final userId = ref.viewedStudentId;
      final data = await supabase
          .from('in_app_notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(200);
      setState(() {
        _notifications = (data as List)
            .map((e) => InAppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(InAppNotification n) async {
    if (!n.isUnread) return;
    try {
      await supabase
          .from('in_app_notifications')
          .update({'read_at': DateTime.now().toIso8601String()}).eq('id', n.id);
      ref.invalidate(unreadNotificationCountProvider);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _markAllRead() async {
    try {
      final userId = ref.viewedStudentId;
      await supabase
          .from('in_app_notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('user_id', userId)
          .isFilter('read_at', null);
      ref.invalidate(unreadNotificationCountProvider);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'low_attendance':
        return Icons.warning_amber_rounded;
      case 'noticeboard':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'low_attendance':
        return Colors.orange;
      case 'noticeboard':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _load());
    final hasUnread = _notifications.any((n) => n.isUnread);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('No notifications yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final n = _notifications[i];
                      final color = _colorFor(n.type);
                      return Card(
                        color: n.isUnread ? color.withValues(alpha: 0.08) : null,
                        child: ListTile(
                          leading: Icon(_iconFor(n.type), color: color),
                          title: Text(n.title,
                              style: TextStyle(fontWeight: n.isUnread ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(
                              '${n.body}\n${DateFormat('d MMM yyyy, h:mm a').format(n.createdAt)}'),
                          isThreeLine: true,
                          trailing: n.isUnread
                              ? Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                )
                              : null,
                          onTap: () => _markRead(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
