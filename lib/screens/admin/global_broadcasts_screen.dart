import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/announcement.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/broadcast_media_service.dart';
import 'package:school_management_app/widgets/media_attachment_preview.dart';
import 'package:school_management_app/utils/error_messages.dart';

class GlobalBroadcastsScreen extends StatefulWidget {
  const GlobalBroadcastsScreen({super.key});

  @override
  State<GlobalBroadcastsScreen> createState() => _GlobalBroadcastsScreenState();
}

class _GlobalBroadcastsScreenState extends State<GlobalBroadcastsScreen> {
  bool _loading = true;
  List<Announcement> _announcements = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('announcements')
          .select('*, profiles!announcements_author_id_fkey(full_name)')
          .isFilter('class_id', null)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      setState(() {
        _announcements = (data as List)
            .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
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

  Future<void> _compose() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String? mediaUrl;
    bool uploadingMedia = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Broadcast'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: uploadingMedia
                      ? null
                      : () async {
                          setDialogState(() => uploadingMedia = true);
                          try {
                            final url = await BroadcastMediaService.pickAndUpload();
                            setDialogState(() => mediaUrl = url ?? mediaUrl);
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(content: Text(friendlyErrorMessage(e))));
                            }
                          } finally {
                            setDialogState(() => uploadingMedia = false);
                          }
                        },
                  icon: uploadingMedia
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file),
                  label: Text(mediaUrl == null ? 'Attach a file (photo, video, PDF, document)' : 'File attached'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
                try {
                  await supabase.from('announcements').insert({
                    'author_id': supabase.auth.currentUser!.id,
                    'class_id': null,
                    'title': titleCtrl.text.trim(),
                    'body': bodyCtrl.text.trim(),
                    'media_url': mediaUrl,
                  });
                  final recipients = await supabase.from('profiles').select('id');
                  await supabase.from('in_app_notifications').insert([
                    for (final r in (recipients as List))
                      {
                        'user_id': r['id'],
                        'title': titleCtrl.text.trim(),
                        'body': bodyCtrl.text.trim(),
                        'type': 'noticeboard',
                      },
                  ]);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _fetch();
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Announcement a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this broadcast?'),
        content: const Text('This removes it from everyone\'s view. This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.from('announcements').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': supabase.auth.currentUser?.id,
      }).eq('id', a.id);
      await AuditService.log(module: 'broadcasts', action: 'delete', oldValue: {'title': a.title});
      await _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global Broadcasts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
              ? const Center(child: Text('No broadcasts posted yet'))
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _announcements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final a = _announcements[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                leading:
                                    const Icon(Icons.campaign_rounded, color: Colors.purple),
                                title: Text(a.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '${a.body}\n${DateFormat.yMMMd().add_jm().format(a.createdAt)}'),
                                isThreeLine: true,
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _delete(a),
                                ),
                              ),
                              if (a.mediaUrl != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                  child: MediaAttachmentPreview(url: a.mediaUrl!),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.add),
        label: const Text('Broadcast'),
      ),
    );
  }
}
