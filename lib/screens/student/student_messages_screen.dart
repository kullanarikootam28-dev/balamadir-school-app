import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';

class StudentMessagesScreen extends ConsumerStatefulWidget {
  const StudentMessagesScreen({super.key});

  @override
  ConsumerState<StudentMessagesScreen> createState() => _StudentMessagesScreenState();
}

class _StudentMessagesScreenState extends ConsumerState<StudentMessagesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _teachers = [];

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    setState(() => _loading = true);
    try {
      final studentId = ref.viewedStudentId;
      final enrollment = await supabase
          .from('class_students')
          .select('class_id, classes(teacher_id)')
          .eq('student_id', studentId)
          .maybeSingle();

      if (enrollment == null) {
        setState(() => _teachers = []);
        return;
      }

      final classId = enrollment['class_id'] as String;
      final subjectTeachers = await supabase
          .from('class_subject_teachers')
          .select('profiles(id, full_name)')
          .eq('class_id', classId);

      final seen = <String>{};
      final teachers = <Map<String, dynamic>>[];
      for (final row in (subjectTeachers as List)) {
        final p = (row as Map<String, dynamic>)['profiles'] as Map<String, dynamic>?;
        if (p != null && seen.add(p['id'] as String)) {
          teachers.add({'id': p['id'], 'name': p['full_name']});
        }
      }

      final homeroomTeacherId =
          (enrollment['classes'] as Map<String, dynamic>?)?['teacher_id'] as String?;
      if (homeroomTeacherId != null && seen.add(homeroomTeacherId)) {
        final p = await supabase
            .from('profiles')
            .select('id, full_name')
            .eq('id', homeroomTeacherId)
            .maybeSingle();
        if (p != null) teachers.add({'id': p['id'], 'name': p['full_name']});
      }

      setState(() => _teachers = teachers);
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
    ref.listen(viewedStudentIdProvider, (_, __) => _loadTeachers());
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _teachers.isEmpty
              ? const Center(child: Text('No teachers to message yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _teachers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = _teachers[i];
                    final name = t['name'] as String? ?? '—';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                            child: Text(name.isNotEmpty ? name[0] : '?')),
                        title: Text(name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          '/messages/${t['id']}',
                          extra: name,
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
