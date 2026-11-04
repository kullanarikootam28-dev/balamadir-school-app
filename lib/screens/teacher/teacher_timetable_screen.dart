import 'package:flutter/material.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/timetable_slot.dart';
import 'package:school_management_app/widgets/timetable_grid.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// A teacher's own weekly timetable, spanning every class they teach —
/// unlike the admin/student grids (scoped to one class), each cell here
/// shows which class a period is for (TimetableSlot.className / the
/// TimetableGrid fallback added for this), since the same teacher can teach
/// different classes in different periods.
class TeacherTimetableScreen extends StatefulWidget {
  const TeacherTimetableScreen({super.key});

  @override
  State<TeacherTimetableScreen> createState() => _TeacherTimetableScreenState();
}

class _TeacherTimetableScreenState extends State<TeacherTimetableScreen> {
  bool _loading = true;
  List<TimetableSlot> _slots = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final teacherId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('timetable_slots')
          .select('*, subjects(name), classes(grade, section)')
          .eq('teacher_id', teacherId);
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
    return Scaffold(
      appBar: AppBar(title: const Text('My Timetable')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _slots.isEmpty
              ? const Center(child: Text('No timetable periods assigned to you yet'))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: TimetableGrid(slots: _slots),
                ),
    );
  }
}
