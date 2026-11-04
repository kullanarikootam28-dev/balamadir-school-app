import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/staff.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 4 of the client spec: Non-Teaching Staff Management.
class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  bool _loading = true;
  List<NonTeachingStaff> _staff = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await supabase.from('non_teaching_staff').select().order('full_name');
      setState(() {
        _staff = (data as List)
            .map((e) => NonTeachingStaff.fromJson(e as Map<String, dynamic>))
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

  Future<void> _openDialog({NonTeachingStaff? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.fullName ?? '');
    final designationCtrl = TextEditingController(text: existing?.designation ?? '');
    final departmentCtrl = TextEditingController(text: existing?.department ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final salaryCtrl = TextEditingController(
        text: existing?.salaryPaise != null
            ? (existing!.salaryPaise! / 100).toStringAsFixed(2)
            : '');
    final remarksCtrl = TextEditingController(text: existing?.remarks ?? '');
    StaffStatus status = existing?.status ?? StaffStatus.active;
    DateTime? joiningDate = existing?.joiningDate;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New Staff Member' : 'Edit Staff Member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full name')),
                TextField(
                    controller: designationCtrl,
                    decoration: const InputDecoration(labelText: 'Designation')),
                TextField(
                    controller: departmentCtrl,
                    decoration: const InputDecoration(labelText: 'Department (optional)')),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (optional)')),
                TextField(
                  controller: salaryCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Salary (₹, optional)'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Joining date'),
                  subtitle: Text(joiningDate != null
                      ? DateFormat('d MMM yyyy').format(joiningDate!)
                      : 'Not set'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: joiningDate ?? DateTime.now(),
                      firstDate: DateTime(1990),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => joiningDate = picked);
                  },
                ),
                DropdownButtonFormField<StaffStatus>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: StaffStatus.active, child: Text('ACTIVE')),
                    DropdownMenuItem(value: StaffStatus.onLeave, child: Text('ON LEAVE')),
                    DropdownMenuItem(value: StaffStatus.resigned, child: Text('RESIGNED')),
                  ],
                  onChanged: (v) => setDialogState(() => status = v!),
                ),
                TextField(
                  controller: remarksCtrl,
                  decoration: const InputDecoration(labelText: 'Remarks (optional)'),
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
                if (nameCtrl.text.trim().isEmpty || designationCtrl.text.trim().isEmpty) return;
                try {
                  final payload = {
                    'full_name': nameCtrl.text.trim(),
                    'designation': designationCtrl.text.trim(),
                    'department':
                        departmentCtrl.text.trim().isEmpty ? null : departmentCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    'salary_paise': salaryCtrl.text.trim().isEmpty
                        ? null
                        : (double.parse(salaryCtrl.text.trim()) * 100).round(),
                    'joining_date': joiningDate?.toIso8601String().substring(0, 10),
                    'status': status == StaffStatus.onLeave
                        ? 'on_leave'
                        : status == StaffStatus.resigned
                            ? 'resigned'
                            : 'active',
                    'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
                  };
                  if (existing == null) {
                    await supabase.from('non_teaching_staff').insert(payload);
                  } else {
                    await supabase
                        .from('non_teaching_staff')
                        .update(payload)
                        .eq('id', existing.id);
                  }
                  await AuditService.log(
                    module: 'staff',
                    action: existing == null ? 'create' : 'update',
                    newValue: payload,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(NonTeachingStaff s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove staff member?'),
        content: Text('This removes ${s.fullName} from staff records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await supabase.from('non_teaching_staff').delete().eq('id', s.id);
    await AuditService.log(module: 'staff', action: 'delete', oldValue: s.toJson());
    await _load();
  }

  Color _statusColor(StaffStatus s) {
    switch (s) {
      case StaffStatus.active:
        return Colors.green;
      case StaffStatus.onLeave:
        return Colors.orange;
      case StaffStatus.resigned:
        return Colors.grey;
    }
  }

  Future<void> _exportAll() async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'non_teaching_staff',
        headers: const [
          'Name',
          'Designation',
          'Department',
          'Phone',
          'Salary',
          'Joining Date',
          'Status',
          'Remarks',
        ],
        rows: _staff
            .map((s) => [
                  s.fullName,
                  s.designation,
                  s.department ?? '',
                  s.phone ?? '',
                  s.salaryDisplay,
                  s.joiningDate != null ? DateFormat('yyyy-MM-dd').format(s.joiningDate!) : '',
                  s.status.name,
                  s.remarks ?? '',
                ])
            .toList(),
      );
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
      appBar: AppBar(
        title: const Text('Non-Teaching Staff'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Export all as Excel',
            onPressed: _staff.isEmpty ? null : _exportAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? const Center(child: Text('No staff records yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _staff.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = _staff[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(s.status).withValues(alpha: 0.15),
                            child: Icon(Icons.badge_outlined, color: _statusColor(s.status)),
                          ),
                          title: Text(s.fullName),
                          subtitle: Text(
                              '${s.designation}${s.department != null ? ' · ${s.department}' : ''}\n${s.salaryDisplay} · ${s.status.name.toUpperCase()}'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _openDialog(existing: s),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _delete(s),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Staff'),
      ),
    );
  }
}
