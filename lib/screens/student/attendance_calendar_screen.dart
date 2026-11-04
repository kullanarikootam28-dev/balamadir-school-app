import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';

const double kRequiredAttendancePercent = 75.0;

class AttendanceCalendarScreen extends ConsumerStatefulWidget {
  const AttendanceCalendarScreen({super.key});

  @override
  ConsumerState<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState extends ConsumerState<AttendanceCalendarScreen> {
  bool _loading = true;
  final Map<DateTime, String> _statusByDay = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _fetchAttendance();
  }

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _fetchAttendance() async {
    setState(() => _loading = true);
    try {
      final studentId = ref.viewedStudentId;
      final data = await supabase
          .from(SupabaseConfig.attendanceTable)
          .select('date, status')
          .eq('student_id', studentId);

      _statusByDay.clear();
      for (final row in (data as List)) {
        final r = row as Map<String, dynamic>;
        final date = DateTime.parse(r['date'] as String);
        _statusByDay[_normalize(date)] = r['status'] as String;
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _colorFor(String? status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'excused':
        return Colors.blueGrey;
      case 'half_day':
        return Colors.purple;
      default:
        return Colors.transparent;
    }
  }

  ({double attended, int total, double percent}) get _stats {
    final total = _statusByDay.length;
    final attended = _statusByDay.values.fold<double>(0, (sum, s) {
      if (s == 'present' || s == 'late') return sum + 1;
      if (s == 'half_day') return sum + 0.5;
      return sum;
    });
    final percent = total == 0 ? 0.0 : (attended / total) * 100;
    return (attended: attended, total: total, percent: percent);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _fetchAttendance());
    final stats = _stats;
    final meetsRequirement = stats.percent >= kRequiredAttendancePercent;

    return Scaffold(
      appBar: AppBar(title: Text(ref.familyTitle('Attendance Calendar'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  color: meetsRequirement
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          meetsRequirement ? Icons.check_circle : Icons.warning_rounded,
                          color: meetsRequirement ? Colors.green : Colors.red,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${stats.percent.toStringAsFixed(1)}% attendance',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Required: ${kRequiredAttendancePercent.toStringAsFixed(0)}% · '
                                '${stats.attended}/${stats.total} days present',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TableCalendar(
                  firstDay: DateTime(2020),
                  lastDay: DateTime.now().add(const Duration(days: 1)),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) => _focusedDay = focused,
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) =>
                        _buildDayCell(day),
                    todayBuilder: (context, day, focusedDay) =>
                        _buildDayCell(day, isToday: true),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  children: [
                    _legendDot('Present', Colors.green),
                    _legendDot('Absent', Colors.red),
                    _legendDot('Late', Colors.orange),
                    _legendDot('Excused', Colors.blueGrey),
                    _legendDot('Half Day', Colors.purple),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildDayCell(DateTime day, {bool isToday = false}) {
    final status = _statusByDay[_normalize(day)];
    final color = _colorFor(status);
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: status == null ? 0 : 0.25),
        shape: BoxShape.circle,
        border: isToday ? Border.all(color: Colors.blue, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text('${day.day}'),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
