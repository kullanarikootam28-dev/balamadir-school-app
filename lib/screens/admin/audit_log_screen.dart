import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/audit_log_entry.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 22 of the client spec: track every action, who did it, in what
/// role, module, old/new value, and when.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  bool _loading = true;
  List<AuditLogEntry> _entries = [];
  String _moduleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('audit_log')
          .select()
          .order('created_at', ascending: false)
          .limit(300);
      setState(() {
        _entries = (data as List)
            .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
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
    final modules = <String>{'all', ..._entries.map((e) => e.module)}.toList();
    final filtered = _moduleFilter == 'all'
        ? _entries
        : _entries.where((e) => e.module == _moduleFilter).toList();

    Future<void> exportAll() async {
      try {
        await ExcelExportService.exportRows(
          fileBaseName: 'audit_log',
          headers: const ['Module', 'Action', 'Actor Role', 'Date'],
          rows: filtered
              .map((e) => [
                    e.module,
                    e.action,
                    e.actorRole ?? 'unknown',
                    DateFormat('yyyy-MM-dd HH:mm').format(e.createdAt),
                  ])
              .toList(),
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Export as Excel',
            onPressed: filtered.isEmpty ? null : exportAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: modules
                          .map((m) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(m.toUpperCase()),
                                  selected: _moduleFilter == m,
                                  onSelected: (_) => setState(() => _moduleFilter = m),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No audit entries yet'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final e = filtered[i];
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  title: Text('${e.module} · ${e.action}'),
                                  subtitle: Text(
                                      'By ${e.actorRole ?? 'unknown'} · ${DateFormat('d MMM yyyy, h:mm a').format(e.createdAt)}'),
                                  trailing: (e.oldValue != null || e.newValue != null)
                                      ? IconButton(
                                          icon: const Icon(Icons.info_outline, size: 18),
                                          onPressed: () => showDialog<void>(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: Text('${e.module} · ${e.action}'),
                                              content: SingleChildScrollView(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    if (e.oldValue != null) ...[
                                                      const Text('Old value:',
                                                          style: TextStyle(fontWeight: FontWeight.bold)),
                                                      Text('${e.oldValue}'),
                                                      const SizedBox(height: 8),
                                                    ],
                                                    if (e.newValue != null) ...[
                                                      const Text('New value:',
                                                          style: TextStyle(fontWeight: FontWeight.bold)),
                                                      Text('${e.newValue}'),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context),
                                                  child: const Text('Close'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
