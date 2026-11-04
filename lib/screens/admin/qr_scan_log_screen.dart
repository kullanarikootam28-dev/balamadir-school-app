import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Full audit trail for the QR attendance system — every scan attempt,
/// successful or not, as required by module 3 ("failed attempts and
/// system-generated codes used").
class QrScanLogScreen extends StatefulWidget {
  const QrScanLogScreen({super.key});

  @override
  State<QrScanLogScreen> createState() => _QrScanLogScreenState();
}

class _QrScanLogScreenState extends State<QrScanLogScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _log = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('qr_scan_log')
          .select('*, profiles(full_name)')
          .order('scanned_at', ascending: false)
          .limit(300);
      setState(() => _log = List<Map<String, dynamic>>.from(data));
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
    final filtered = _filter == 'all'
        ? _log
        : _log.where((r) => (r['success'] as bool) == (_filter == 'success')).toList();

    Future<void> exportAll() async {
      try {
        await ExcelExportService.exportRows(
          fileBaseName: 'qr_scan_log',
          headers: const ['Name', 'Success', 'Reason', 'Scanned At'],
          rows: filtered
              .map((r) => [
                    (r['profiles'] as Map?)?['full_name'] as String? ?? 'Unknown',
                    (r['success'] as bool) ? 'Success' : 'Failed',
                    r['reason'] ?? '',
                    DateFormat('yyyy-MM-dd HH:mm:ss')
                        .format(DateTime.parse(r['scanned_at'] as String)),
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
        title: const Text('QR Scan Log'),
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
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final f in const ['all', 'success', 'failed'])
                        ChoiceChip(
                          label: Text(f.toUpperCase()),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No scan attempts yet'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final r = filtered[i];
                              final success = r['success'] as bool;
                              final name =
                                  (r['profiles'] as Map?)?['full_name'] as String? ?? 'Unknown';
                              final scannedAt = DateTime.parse(r['scanned_at'] as String);
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    success ? Icons.check_circle : Icons.cancel,
                                    color: success ? Colors.green : Colors.red,
                                  ),
                                  title: Text(name),
                                  subtitle: Text(
                                      '${r['reason'] ?? '—'} · ${DateFormat('d MMM yyyy, h:mm:ss a').format(scannedAt)}'),
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
