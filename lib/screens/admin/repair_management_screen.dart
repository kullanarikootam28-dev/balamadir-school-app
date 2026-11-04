import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/repair_request.dart';
import 'package:school_management_app/screens/admin/repair_detail_screen.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

const kRepairLocations = ['Classroom', 'Office', 'Lab', 'Bathroom', 'Bus', 'Other'];
const kRepairCategories = ['Electrical', 'Plumbing', 'Furniture', 'Computer', 'Building', 'Other'];

Color repairStatusColor(RepairStatus status) {
  switch (status) {
    case RepairStatus.reported:
      return Colors.orange;
    case RepairStatus.approved:
      return Colors.blue;
    case RepairStatus.inProgress:
      return Colors.purple;
    case RepairStatus.completed:
      return Colors.green;
    case RepairStatus.cancelled:
      return Colors.grey;
  }
}

/// Repair request list + creation dialog. Editing an existing request's full
/// lifecycle (status, costs, photo/quotation uploads) happens in
/// repair_detail_screen.dart, same split as student_records_screen.dart's
/// list-then-detail-screen pattern.
class RepairManagementScreen extends StatefulWidget {
  const RepairManagementScreen({super.key});

  @override
  State<RepairManagementScreen> createState() => _RepairManagementScreenState();
}

class _RepairManagementScreenState extends State<RepairManagementScreen> {
  bool _loading = true;
  List<RepairRequest> _repairs = [];
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('repair_requests')
          .select()
          .isFilter('deleted_at', null)
          .order('reported_date', ascending: false);
      setState(() {
        _repairs = (data as List)
            .map((e) => RepairRequest.fromJson(e as Map<String, dynamic>))
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

  List<RepairRequest> get _filtered => _statusFilter == 'all'
      ? _repairs
      : _repairs.where((r) => repairStatusToJson(r.status) == _statusFilter).toList();

  Future<void> _openNewRequestDialog() async {
    String location = kRepairLocations.first;
    String category = kRepairCategories.first;
    final descCtrl = TextEditingController();
    final responsibleCtrl = TextEditingController();
    final estimateCtrl = TextEditingController();
    DateTime reportedDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Repair Request'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: location,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: kRepairLocations
                        .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => location = v!),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Repair category'),
                    items: kRepairCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => category = v!),
                  ),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Describe the problem'),
                    maxLines: 2,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reported date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(reportedDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: reportedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => reportedDate = picked);
                    },
                  ),
                  TextFormField(
                    controller: responsibleCtrl,
                    decoration: const InputDecoration(labelText: 'Responsible person/vendor (optional)'),
                  ),
                  TextFormField(
                    controller: estimateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Estimated cost (₹, optional)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final payload = {
                    'location': location,
                    'category': category,
                    'description': descCtrl.text.trim(),
                    'reported_date': reportedDate.toIso8601String().substring(0, 10),
                    'responsible_person':
                        responsibleCtrl.text.trim().isEmpty ? null : responsibleCtrl.text.trim(),
                    'estimated_cost_paise': estimateCtrl.text.trim().isEmpty
                        ? null
                        : (double.parse(estimateCtrl.text.trim()) * 100).round(),
                    'status': 'reported',
                    'created_by': supabase.auth.currentUser?.id,
                  };
                  await supabase.from('repair_requests').insert(payload);
                  await AuditService.log(module: 'repairs', action: 'create', newValue: payload);
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Repair & Maintenance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final s in const ['all', 'reported', 'approved', 'in_progress', 'completed', 'cancelled'])
                        ChoiceChip(
                          label: Text(s == 'all' ? 'ALL' : repairStatusLabel(repairStatusFromJson(s)).toUpperCase()),
                          selected: _statusFilter == s,
                          onSelected: (_) => setState(() => _statusFilter = s),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No repair requests'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final r = filtered[i];
                              final color = repairStatusColor(r.status);
                              return Card(
                                child: ListTile(
                                  leading: Icon(Icons.build_outlined, color: color),
                                  title: Text('${r.location} · ${r.category}'),
                                  subtitle: Text(
                                    '${r.description}\nReported ${DateFormat('d MMM yyyy').format(r.reportedDate)}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Chip(
                                    label: Text(repairStatusLabel(r.status)),
                                    backgroundColor: color.withValues(alpha: 0.15),
                                    labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
                                  ),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => RepairDetailScreen(repair: r)),
                                    );
                                    await _load();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewRequestDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
    );
  }
}
