import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Complaints are submitted with no author attached (see
/// complaint_box_screen.dart), so this is deliberately just a flat,
/// unattributed list — no status workflow, matching the anonymous design.
/// Deletion is soft (deleted_at/deleted_by, 016_soft_deletes.sql) and has no
/// "notify the submitter" step, since there's no submitter to notify.
class ComplaintReportScreen extends StatefulWidget {
  const ComplaintReportScreen({super.key});

  @override
  State<ComplaintReportScreen> createState() => _ComplaintReportScreenState();
}

class _ComplaintReportScreenState extends State<ComplaintReportScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _complaints = [];
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('complaints')
          .select()
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      setState(() => _complaints = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _softDelete(List<String> ids) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ids.length == 1 ? 'Delete complaint?' : 'Delete ${ids.length} complaints?'),
        content: const Text(
            "This removes the complaint(s) from this list. They can't be undone by the sender since complaints are anonymous."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await supabase.from('complaints').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': supabase.auth.currentUser?.id,
      }).inFilter('id', ids);
      await AuditService.log(
        module: 'complaints',
        action: 'delete',
        oldValue: {'count': ids.length},
      );
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _exportAll() async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'complaint_reports',
        headers: const ['Message', 'Submitted At'],
        rows: _complaints
            .map((c) => [
                  c['message'],
                  DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(c['created_at'] as String)),
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
        title: Text(_selectionMode ? '${_selectedIds.length} selected' : 'Complaint Reports'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        actions: [
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete selected',
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _softDelete(_selectedIds.toList()),
            )
          else ...[
            if (_complaints.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.table_view_outlined),
                tooltip: 'Export all as Excel',
                onPressed: _exportAll,
              ),
            if (_complaints.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.checklist_outlined),
                tooltip: 'Select multiple',
                onPressed: () => setState(() => _selectionMode = true),
              ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _complaints.isEmpty
              ? const Center(child: Text('No complaints submitted yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _complaints.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = _complaints[i];
                      final id = c['id'] as String;
                      final createdAt = DateTime.parse(c['created_at'] as String);
                      final selected = _selectedIds.contains(id);
                      return Card(
                        child: ListTile(
                          leading: _selectionMode
                              ? Checkbox(
                                  value: selected,
                                  onChanged: (checked) => setState(() {
                                    if (checked == true) {
                                      _selectedIds.add(id);
                                    } else {
                                      _selectedIds.remove(id);
                                    }
                                  }),
                                )
                              : const Icon(Icons.report_outlined),
                          title: Text(c['message'] as String),
                          subtitle: Text(DateFormat('d MMM yyyy, h:mm a').format(createdAt)),
                          trailing: _selectionMode
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _softDelete([id]),
                                ),
                          onLongPress: () => setState(() {
                            _selectionMode = true;
                            _selectedIds.add(id);
                          }),
                          onTap: _selectionMode
                              ? () => setState(() {
                                    if (selected) {
                                      _selectedIds.remove(id);
                                    } else {
                                      _selectedIds.add(id);
                                    }
                                  })
                              : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
