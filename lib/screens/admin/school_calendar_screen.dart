import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/calendar_event.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 15 of the client spec: Holidays, Events, Exams, Sports/Annual Day.
/// Admin manages entries here; teachers and students view the same calendar
/// read-only (route `/calendar`, [readOnly] true) — RLS already lets any
/// authenticated user read `calendar_events`, only admin could ever write.
class SchoolCalendarScreen extends StatefulWidget {
  const SchoolCalendarScreen({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  State<SchoolCalendarScreen> createState() => _SchoolCalendarScreenState();
}

class _SchoolCalendarScreenState extends State<SchoolCalendarScreen> {
  bool _loading = true;
  List<CalendarEvent> _events = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase.from('calendar_events').select().order('event_date');
      setState(() {
        _events = (data as List)
            .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
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

  List<CalendarEvent> _eventsOn(DateTime day) {
    return _events.where((e) {
      final end = e.endDate ?? e.eventDate;
      final d = DateTime(day.year, day.month, day.day);
      return !d.isBefore(DateTime(e.eventDate.year, e.eventDate.month, e.eventDate.day)) &&
          !d.isAfter(DateTime(end.year, end.month, end.day));
    }).toList();
  }

  Color _colorFor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.holiday:
        return Colors.red;
      case CalendarEventType.exam:
        return Colors.purple;
      case CalendarEventType.sportsDay:
        return Colors.orange;
      case CalendarEventType.annualDay:
        return Colors.teal;
      case CalendarEventType.event:
        return Colors.blue;
    }
  }

  String _labelFor(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.holiday:
        return 'Holiday';
      case CalendarEventType.exam:
        return 'Exam';
      case CalendarEventType.sportsDay:
        return 'Sports Day';
      case CalendarEventType.annualDay:
        return 'Annual Day';
      case CalendarEventType.event:
        return 'Event';
    }
  }

  Future<void> _createEvent() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    CalendarEventType type = CalendarEventType.event;
    DateTime eventDate = _selectedDay ?? DateTime.now();
    DateTime? endDate;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Calendar Entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                DropdownButtonFormField<CalendarEventType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: CalendarEventType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(_labelFor(t))))
                      .toList(),
                  onChanged: (v) => setDialogState(() => type = v!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(DateFormat('d MMM yyyy').format(eventDate)),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: eventDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (picked != null) setDialogState(() => eventDate = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End date (optional, for multi-day)'),
                  subtitle: Text(endDate != null ? DateFormat('d MMM yyyy').format(endDate!) : 'Same as start'),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: eventDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (picked != null) setDialogState(() => endDate = picked);
                  },
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                try {
                  await supabase.from('calendar_events').insert({
                    'title': titleCtrl.text.trim(),
                    'event_type': CalendarEvent(
                      id: '',
                      title: '',
                      eventType: type,
                      eventDate: eventDate,
                    ).toJson()['event_type'],
                    'event_date': eventDate.toIso8601String().substring(0, 10),
                    'end_date': endDate?.toIso8601String().substring(0, 10),
                    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'created_by': supabase.auth.currentUser?.id,
                  });
                  await AuditService.log(
                      module: 'calendar', action: 'create', newValue: {'title': titleCtrl.text.trim()});
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(CalendarEvent e) async {
    await supabase.from('calendar_events').delete().eq('id', e.id);
    await AuditService.log(module: 'calendar', action: 'delete', oldValue: {'title': e.title});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsOn(_selectedDay ?? _focusedDay);
    return Scaffold(
      appBar: AppBar(title: const Text('School Calendar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TableCalendar(
                  firstDay: DateTime(2020),
                  lastDay: DateTime(2100),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selected, focused) =>
                      setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  }),
                  onPageChanged: (focused) => _focusedDay = focused,
                  eventLoader: _eventsOn,
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) return null;
                      final e = events.first as CalendarEvent;
                      return Container(
                        margin: const EdgeInsets.only(top: 28),
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: _colorFor(e.eventType), shape: BoxShape.circle),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                    _selectedDay != null
                        ? DateFormat('EEEE, d MMM yyyy').format(_selectedDay!)
                        : 'All upcoming entries',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (dayEvents.isEmpty)
                  const Padding(padding: EdgeInsets.all(8), child: Text('No entries on this day'))
                else
                  ...dayEvents.map((e) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _colorFor(e.eventType).withValues(alpha: 0.15),
                            child: Icon(Icons.event, color: _colorFor(e.eventType)),
                          ),
                          title: Text(e.title),
                          subtitle: Text('${_labelFor(e.eventType)}${e.description != null ? ' · ${e.description}' : ''}'),
                          trailing: widget.readOnly
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _delete(e),
                                ),
                        ),
                      )),
              ],
            ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _createEvent,
              icon: const Icon(Icons.add),
              label: const Text('Entry'),
            ),
    );
  }
}
