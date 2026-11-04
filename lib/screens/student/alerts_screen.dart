import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/announcement.dart';
import 'package:school_management_app/widgets/media_attachment_preview.dart';
import 'package:school_management_app/utils/error_messages.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
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
      final studentId = ref.viewedStudentId;
      final enrollment = await supabase
          .from('class_students')
          .select('class_id')
          .eq('student_id', studentId)
          .maybeSingle();

      final global = await supabase
          .from('announcements')
          .select('*, profiles!announcements_author_id_fkey(full_name)')
          .isFilter('class_id', null)
          .isFilter('deleted_at', null);

      List<dynamic> classSpecific = [];
      if (enrollment != null) {
        classSpecific = await supabase
            .from('announcements')
            .select('*, profiles!announcements_author_id_fkey(full_name)')
            .eq('class_id', enrollment['class_id'] as String)
            .isFilter('deleted_at', null);
      }

      final all = [...(global as List), ...classSpecific]
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() => _announcements = all);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _fetch());
    return Scaffold(
      appBar: AppBar(title: Text(ref.familyTitle('Alerts Dashboard'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
              ? const Center(child: Text('No alerts yet'))
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
                                leading: Icon(
                                  a.isGlobal ? Icons.campaign_rounded : Icons.announcement_rounded,
                                  color: a.isGlobal ? Colors.purple : Colors.blue,
                                ),
                                title: Text(a.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '${a.body}\n${a.authorName ?? (a.isGlobal ? 'School Administration' : '')} · ${DateFormat.yMMMd().add_jm().format(a.createdAt)}'),
                                isThreeLine: true,
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
    );
  }
}
