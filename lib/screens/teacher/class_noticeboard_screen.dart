import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/announcement.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/broadcast_media_service.dart';
import 'package:school_management_app/widgets/media_attachment_preview.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// A teacher's noticeboard: notices for the selected class (which they can
/// post, and delete if they wrote them) plus the admin's school-wide
/// broadcasts (read-only, labelled "School-wide") so teachers see the same
/// announcements their students do.
class ClassNoticeboardScreen extends StatefulWidget {
  const ClassNoticeboardScreen({super.key});

  @override
  State<ClassNoticeboardScreen> createState() => _ClassNoticeboardScreenState();
}

class _ClassNoticeboardScreenState extends State<ClassNoticeboardScreen> {
  bool _loading = true;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  List<Announcement> _announcements = [];

  @override
  void initState() {
    super.initState();
    _loadMyClasses();
  }

  Future<void> _loadMyClasses() async {
    setState(() => _loading = true);
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final assigned = await supabase
          .from('class_subject_teachers')
          .select('classes(*)')
          .eq('teacher_id', teacherId);
      final homeroom = await supabase
          .from(SupabaseConfig.classesTable)
          .select()
          .eq('teacher_id', teacherId);

      final seen = <String>{};
      final classes = <ClassModel>[];
      for (final row in (assigned as List)) {
        final c = (row as Map<String, dynamic>)['classes'];
        if (c != null && seen.add((c as Map<String, dynamic>)['id'] as String)) {
          classes.add(ClassModel.fromJson(c));
        }
      }
      for (final row in (homeroom as List)) {
        final c = row as Map<String, dynamic>;
        if (seen.add(c['id'] as String)) classes.add(ClassModel.fromJson(c));
      }

      setState(() => _classes = classes);
      if (classes.isNotEmpty) _selectedClass = classes.first;
      await _loadAnnouncements();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The selected class's notices plus school-wide broadcasts
  /// (class_id null), newest first.
  Future<void> _loadAnnouncements() async {
    final base = supabase
        .from('announcements')
        .select('*, profiles!announcements_author_id_fkey(full_name)')
        .isFilter('deleted_at', null);
    final data = await (_selectedClass == null
            ? base.isFilter('class_id', null)
            : base.or('class_id.eq.${_selectedClass!.id},class_id.is.null'))
        .order('created_at', ascending: false)
        .limit(200);
    setState(() {
      _announcements = (data as List)
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> _compose() async {
    if (_selectedClass == null) return;
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String? mediaUrl;
    bool uploadingMedia = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Post to ${_selectedClass!.displayName}'),
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
                    'class_id': _selectedClass!.id,
                    'title': titleCtrl.text.trim(),
                    'body': bodyCtrl.text.trim(),
                    'media_url': mediaUrl,
                  });
                  await supabase.rpc('notify_class_students', params: {
                    'p_class_id': _selectedClass!.id,
                    'p_title': titleCtrl.text.trim(),
                    'p_body': bodyCtrl.text.trim(),
                    'p_related_id': null,
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadAnnouncements();
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
        title: const Text('Delete this notice?'),
        content: const Text('This removes it from the class noticeboard. This can\'t be undone.'),
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
      await _loadAnnouncements();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Class Noticeboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _classes.isEmpty
                      ? const Text(
                          'You are not assigned to any class yet — showing school-wide notices only.')
                      : DropdownButtonFormField<ClassModel>(
                          initialValue: _selectedClass,
                          decoration: const InputDecoration(labelText: 'Class'),
                          items: _classes
                              .map((c) => DropdownMenuItem(
                                  value: c, child: Text(c.displayName)))
                              .toList(),
                          onChanged: (c) {
                            setState(() => _selectedClass = c);
                            _loadAnnouncements();
                          },
                        ),
                ),
                Expanded(
                  child: _announcements.isEmpty
                      ? const Center(child: Text('No notices posted yet'))
                      : RefreshIndicator(
                          onRefresh: _loadAnnouncements,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _announcements.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final a = _announcements[i];
                              final meta = [
                                if (a.isGlobal) 'School-wide',
                                DateFormat.yMMMd().add_jm().format(a.createdAt.toLocal()),
                                if (a.authorName != null) a.authorName!,
                              ].join(' · ');
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      ListTile(
                                        leading: Icon(
                                            a.isGlobal
                                                ? Icons.campaign_rounded
                                                : Icons.announcement_rounded,
                                            color: a.isGlobal ? Colors.deepOrange : Colors.blue),
                                        title: Text(a.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        subtitle: Text('${a.body}\n$meta'),
                                        isThreeLine: true,
                                        // Teachers can only soft-delete their own
                                        // class notices (RLS); broadcasts are admin's.
                                        trailing: !a.isGlobal && a.authorId == myId
                                            ? IconButton(
                                                icon: const Icon(Icons.delete_outline,
                                                    color: Colors.red),
                                                onPressed: () => _delete(a),
                                              )
                                            : null,
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
                ),
              ],
            ),
      floatingActionButton: _selectedClass == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _compose,
              icon: const Icon(Icons.add),
              label: const Text('Notice'),
            ),
    );
  }
}
