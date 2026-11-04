import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final assigned = await supabase
          .from('class_subject_teachers')
          .select('class_id')
          .eq('teacher_id', teacherId);
      final homeroom = await supabase
          .from('classes')
          .select('id')
          .eq('teacher_id', teacherId);

      final classIds = <String>{
        ...(assigned as List).map((r) => (r as Map)['class_id'] as String),
        ...(homeroom as List).map((r) => (r as Map)['id'] as String),
      };

      if (classIds.isEmpty) {
        setState(() => _students = []);
        return;
      }

      final roster = await supabase
          .from('class_students')
          .select('student_id, profiles(full_name, email)')
          .inFilter('class_id', classIds.toList());

      final seen = <String>{};
      final students = <Map<String, dynamic>>[];
      for (final row in (roster as List)) {
        final r = row as Map<String, dynamic>;
        final id = r['student_id'] as String;
        if (seen.add(id)) {
          students.add({
            'id': id,
            'name': (r['profiles'] as Map?)?['full_name'] as String? ?? '—',
          });
        }
      }
      setState(() => _students = students);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Messaging Portal')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const Center(child: Text('No students to message yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = _students[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                            child: Text((s['name'] as String).isNotEmpty
                                ? (s['name'] as String)[0]
                                : '?')),
                        title: Text(s['name'] as String),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(
                          '/messages/${s['id']}',
                          extra: s['name'],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
