import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/academic_year.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 7 of the client spec: create/switch/archive academic years.
class AcademicYearScreen extends StatefulWidget {
  const AcademicYearScreen({super.key});

  @override
  State<AcademicYearScreen> createState() => _AcademicYearScreenState();
}

class _AcademicYearScreenState extends State<AcademicYearScreen> {
  bool _loading = true;
  List<AcademicYear> _years = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await supabase.from('academic_years').select().order('year_label', ascending: false);
      setState(() {
        _years = (data as List)
            .map((e) => AcademicYear.fromJson(e as Map<String, dynamic>))
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

  Future<void> _create() async {
    final labelCtrl = TextEditingController();
    DateTime? start;
    DateTime? end;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Academic Year'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Year label (e.g. 2026-2027)'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date'),
                subtitle: Text(start != null ? DateFormat('d MMM yyyy').format(start!) : 'Not set'),
                onTap: () async {
                  final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (picked != null) setDialogState(() => start = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End date'),
                subtitle: Text(end != null ? DateFormat('d MMM yyyy').format(end!) : 'Not set'),
                onTap: () async {
                  final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.now().add(const Duration(days: 300)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (picked != null) setDialogState(() => end = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (labelCtrl.text.trim().isEmpty) return;
                try {
                  await supabase.from('academic_years').insert({
                    'year_label': labelCtrl.text.trim(),
                    'start_date': start?.toIso8601String().substring(0, 10),
                    'end_date': end?.toIso8601String().substring(0, 10),
                  });
                  await AuditService.log(
                      module: 'academic_year', action: 'create', newValue: {'year_label': labelCtrl.text.trim()});
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setCurrent(AcademicYear year) async {
    try {
      // Unset any existing current year first — a partial unique index only
      // allows one is_current = true row at a time.
      await supabase.from('academic_years').update({'is_current': false}).eq('is_current', true);
      await supabase.from('academic_years').update({'is_current': true}).eq('id', year.id);
      await AuditService.log(
          module: 'academic_year', action: 'set_current', newValue: {'year_label': year.yearLabel});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _archive(AcademicYear year) async {
    try {
      await supabase.from('academic_years').update({'archived': true}).eq('id', year.id);
      await AuditService.log(
          module: 'academic_year', action: 'archive', oldValue: {'year_label': year.yearLabel});
      await _load();
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
      appBar: AppBar(title: const Text('Academic Years')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _years.isEmpty
              ? const Center(child: Text('No academic years yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _years.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final y = _years[i];
                      return Card(
                        color: y.isCurrent ? Colors.green.withValues(alpha: 0.08) : null,
                        child: ListTile(
                          leading: Icon(
                            y.archived ? Icons.archive_outlined : Icons.event_available,
                            color: y.isCurrent ? Colors.green : null,
                          ),
                          title: Text(y.yearLabel),
                          subtitle: Text(
                            [
                              if (y.startDate != null)
                                DateFormat('d MMM yyyy').format(y.startDate!),
                              if (y.endDate != null) '– ${DateFormat('d MMM yyyy').format(y.endDate!)}',
                              if (y.isCurrent) '· CURRENT',
                              if (y.archived) '· ARCHIVED',
                            ].join(' '),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              if (!y.isCurrent && !y.archived)
                                TextButton(
                                  onPressed: () => _setCurrent(y),
                                  child: const Text('Set current'),
                                ),
                              if (!y.archived)
                                IconButton(
                                  icon: const Icon(Icons.archive_outlined),
                                  tooltip: 'Archive',
                                  onPressed: () => _archive(y),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Academic Year'),
      ),
    );
  }
}
