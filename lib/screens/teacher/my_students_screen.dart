import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';

/// Every student across every class this teacher is assigned to (subject
/// assignments via class_subject_teachers, plus homeroom classes) — one
/// flat, deduplicated roster with photos, tap-through to the full profile.
class MyStudentsScreen extends StatefulWidget {
  const MyStudentsScreen({super.key});

  @override
  State<MyStudentsScreen> createState() => _MyStudentsScreenState();
}

class _MyStudentsScreenState extends State<MyStudentsScreen> {
  bool _loading = true;
  List<Profile> _students = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final results = await Future.wait([
        supabase
            .from('class_subject_teachers')
            .select('class_id')
            .eq('teacher_id', teacherId),
        supabase
            .from('classes')
            .select('id')
            .eq('teacher_id', teacherId),
      ]);
      final classIds = <String>{
        for (final row in results[0] as List) (row as Map<String, dynamic>)['class_id'] as String,
        for (final row in results[1] as List) (row as Map<String, dynamic>)['id'] as String,
      };

      if (classIds.isEmpty) {
        setState(() => _students = []);
        return;
      }

      final roster = await supabase
          .from('class_students')
          .select('profiles(*)')
          .inFilter('class_id', classIds.toList());

      final seen = <String>{};
      final students = <Profile>[];
      for (final row in roster as List) {
        final p = (row as Map<String, dynamic>)['profiles'] as Map<String, dynamic>?;
        if (p != null && seen.add(p['id'] as String)) {
          students.add(Profile.fromJson(p));
        }
      }
      students.sort((a, b) => a.fullName.compareTo(b.fullName));
      setState(() => _students = students);
    } catch (e) {
      setState(() => _error = 'Failed to load students: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Students')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _students.isEmpty
                  ? const Center(child: Text('No students in your assigned classes yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _students.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = _students[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                    s.avatarUrl != null ? NetworkImage(s.avatarUrl!) : null,
                                child: s.avatarUrl == null ? Text(s.fullName[0]) : null,
                              ),
                              title: Text(s.fullName),
                              subtitle: Text(s.email),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/profile/${s.id}'),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
