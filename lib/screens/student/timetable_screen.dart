import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/timetable_slot.dart';
import 'package:school_management_app/widgets/timetable_grid.dart';
import 'package:school_management_app/utils/error_messages.dart';

class StudentTimetableScreen extends ConsumerStatefulWidget {
  const StudentTimetableScreen({super.key});

  @override
  ConsumerState<StudentTimetableScreen> createState() => _StudentTimetableScreenState();
}

class _StudentTimetableScreenState extends ConsumerState<StudentTimetableScreen> {
  bool _loading = true;
  List<TimetableSlot> _slots = [];
  String? _classLabel;

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
          .select('class_id, classes(grade, section)')
          .eq('student_id', studentId)
          .maybeSingle();

      if (enrollment == null) {
        setState(() {
          _slots = [];
          _classLabel = null;
        });
        return;
      }

      final classInfo = enrollment['classes'] as Map<String, dynamic>?;
      _classLabel = classInfo == null
          ? null
          : 'Grade ${classInfo['grade']} – Section ${classInfo['section']}';

      final data = await supabase
          .from('timetable_slots')
          .select('*, subjects(name), profiles(full_name)')
          .eq('class_id', enrollment['class_id'] as String);

      setState(() {
        _slots = (data as List)
            .map((e) => TimetableSlot.fromJson(e as Map<String, dynamic>))
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

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _fetch());
    return Scaffold(
      appBar: AppBar(title: Text(_classLabel ?? 'Daily Timetable')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _classLabel == null
              ? const Center(child: Text('You are not enrolled in a class yet'))
              : _slots.isEmpty
                  ? const Center(child: Text('No timetable has been set up yet'))
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: TimetableGrid(slots: _slots),
                    ),
    );
  }
}
