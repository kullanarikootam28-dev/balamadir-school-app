import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';

class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  List<Map<String, dynamic>> _fees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchFees();
  }

  Future<void> _fetchFees() async {
    setState(() => _loading = true);
    try {
      final userId = ref.viewedStudentId;
      final data = await supabase
          .from(SupabaseConfig.feePaymentsTable)
          .select()
          .eq('student_id', userId)
          .order('due_date', ascending: false);
      setState(() => _fees = List<Map<String, dynamic>>.from(data));
    } catch (_) {
    } finally {
      setState(() => _loading = false);
    }
  }

  (Color, IconData) _statusStyle(String status) {
    switch (status) {
      case 'paid':    return (Colors.green, Icons.check_circle);
      case 'overdue': return (Colors.red,   Icons.warning_rounded);
      case 'waived':  return (Colors.grey,  Icons.remove_circle);
      default:        return (Colors.orange, Icons.schedule);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _fetchFees());
    final totalPending = _fees
        .where((f) => f['status'] == 'pending' || f['status'] == 'overdue')
        .fold<int>(0, (sum, f) => sum + (f['amount_paise'] as int));

    return Scaffold(
      appBar: AppBar(title: Text(ref.familyTitle('Fee Payments'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Summary banner ─────────────────────────────────────────
                if (totalPending > 0)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Text(
                          'Outstanding: ₹${(totalPending / 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                // ── List ───────────────────────────────────────────────────
                Expanded(
                  child: _fees.isEmpty
                      ? const Center(child: Text('No fee records found'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _fees.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final f = _fees[i];
                            final status = f['status'] as String;
                            final (color, icon) = _statusStyle(status);
                            final amt =
                                '₹${((f['amount_paise'] as int) / 100).toStringAsFixed(2)}';
                            final due = f['due_date'] != null
                                ? DateFormat('d MMM yyyy')
                                    .format(DateTime.parse(f['due_date']))
                                : '–';
                            return Card(
                              child: ListTile(
                                leading: Icon(icon, color: color),
                                title: Text(f['description'] ?? f['invoice_id'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                subtitle: Text('Due: $due'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(amt,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: color)),
                                    Text(status.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 10, color: color)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
