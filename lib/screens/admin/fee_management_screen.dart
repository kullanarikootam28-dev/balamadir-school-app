import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/fee_type.dart';
import 'package:school_management_app/models/notification_log.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/notification_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/services/receipt_service.dart';
import 'package:school_management_app/widgets/searchable_picker.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/fetch_all.dart';

const _paymentModes = ['Cash', 'UPI', 'Cheque', 'Bank Transfer', 'Card'];

class FeeManagementScreen extends StatefulWidget {
  const FeeManagementScreen({super.key});

  @override
  State<FeeManagementScreen> createState() => _FeeManagementScreenState();
}

class _FeeManagementScreenState extends State<FeeManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  List<Profile> _students = [];
  List<FeeType> _feeTypes = [];
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        fetchAllRows(() => supabase
            .from(SupabaseConfig.feePaymentsTable)
            .select('*, profiles(full_name, phone)')
            .order('due_date', ascending: false)
            .order('id')),
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'student')
            .order('full_name'),
        supabase.from('fee_types').select().order('name'),
      ]);
      setState(() {
        _payments = List<Map<String, dynamic>>.from(results[0] as List);
        _students = (results[1] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList();
        _feeTypes = (results[2] as List)
            .map((e) => FeeType.fromJson(e as Map<String, dynamic>))
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

  String _studentName(Map<String, dynamic> row) =>
      (row['profiles'] as Map?)?['full_name'] as String? ?? 'Unknown';

  String? _studentPhone(Map<String, dynamic> row) =>
      (row['profiles'] as Map?)?['phone'] as String?;

  String _feeTypeName(String? id) =>
      _feeTypes.firstWhere((f) => f.id == id, orElse: () => const FeeType(id: '', name: 'General')).name;

  List<Map<String, dynamic>> get _filteredPayments {
    if (_statusFilter == 'all') return _payments;
    return _payments.where((p) => p['status'] == _statusFilter).toList();
  }

  (Color, IconData) _statusStyle(String status) {
    switch (status) {
      case 'paid':
        return (Colors.green, Icons.check_circle);
      case 'overdue':
        return (Colors.red, Icons.warning_rounded);
      case 'waived':
        return (Colors.grey, Icons.remove_circle);
      default:
        return (Colors.orange, Icons.schedule);
    }
  }

  Future<void> _openPaymentDialog({Map<String, dynamic>? existing}) async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No student accounts yet')));
      return;
    }
    final formKey = GlobalKey<FormState>();
    final initialStudentId = existing?['student_id'] as String? ?? _students.first.id;
    Profile selectedStudent = _students.firstWhere(
      (s) => s.id == initialStudentId,
      orElse: () => _students.first,
    );
    final amountCtrl = TextEditingController(
        text: existing != null
            ? ((existing['amount_paise'] as int) / 100).toStringAsFixed(2)
            : '');
    final descCtrl = TextEditingController(text: existing?['description'] as String? ?? '');
    String status = existing?['status'] as String? ?? 'pending';
    DateTime dueDate = existing?['due_date'] != null
        ? DateTime.parse(existing!['due_date'] as String)
        : DateTime.now().add(const Duration(days: 14));
    String? feeTypeId = existing?['fee_type_id'] as String? ??
        (_feeTypes.isNotEmpty ? _feeTypes.first.id : null);
    String paymentMode = existing?['payment_mode'] as String? ?? _paymentModes.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New Fee Record' : 'Edit Fee Record'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Student'),
                    subtitle: Text(selectedStudent.fullName),
                    trailing: const Icon(Icons.search),
                    onTap: () async {
                      final picked = await showDialog<Profile>(
                        context: context,
                        builder: (_) => Dialog(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SearchablePicker<Profile>(
                              items: _students,
                              labelOf: (s) => s.fullName,
                              subtitleOf: (s) => s.email,
                              onSelected: (s) => Navigator.pop(context, s),
                            ),
                          ),
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedStudent = picked);
                      }
                    },
                  ),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount (₹)'),
                    validator: (v) {
                      final parsed = double.tryParse(v ?? '');
                      return parsed == null || parsed <= 0 ? 'Enter a valid amount' : null;
                    },
                  ),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                  ),
                  if (_feeTypes.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: feeTypeId,
                      decoration: const InputDecoration(labelText: 'Fee type'),
                      items: _feeTypes
                          .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => feeTypeId = v),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMode,
                    decoration: const InputDecoration(labelText: 'Payment mode'),
                    items: _paymentModes
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => paymentMode = v!),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Due date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(dueDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: dueDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => dueDate = picked);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('PENDING')),
                      DropdownMenuItem(value: 'paid', child: Text('PAID')),
                      DropdownMenuItem(value: 'overdue', child: Text('OVERDUE')),
                      DropdownMenuItem(value: 'waived', child: Text('WAIVED')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final amountPaise = (double.parse(amountCtrl.text) * 100).round();
                  final becomesPaidNow = status == 'paid' && existing?['paid_at'] == null;
                  final payload = {
                    'student_id': selectedStudent.id,
                    'amount_paise': amountPaise,
                    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'due_date': dueDate.toIso8601String().split('T').first,
                    'status': status,
                    'fee_type_id': feeTypeId,
                    'payment_mode': paymentMode,
                    if (becomesPaidNow) 'paid_at': DateTime.now().toIso8601String(),
                    if (becomesPaidNow)
                      'receipt_number': 'RCPT-${DateTime.now().millisecondsSinceEpoch}',
                  };
                  if (existing == null) {
                    await supabase.from(SupabaseConfig.feePaymentsTable).insert({
                      ...payload,
                      'invoice_id': 'INV-${DateTime.now().millisecondsSinceEpoch}',
                    });
                  } else {
                    await supabase
                        .from(SupabaseConfig.feePaymentsTable)
                        .update(payload)
                        .eq('id', existing['id'] as String);
                  }
                  await AuditService.log(
                    module: 'fees',
                    action: existing == null ? 'create' : 'update',
                    oldValue: existing,
                    newValue: payload,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadAll();
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

  Future<void> _markPaid(Map<String, dynamic> row) async {
    try {
      await supabase.from(SupabaseConfig.feePaymentsTable).update({
        'status': 'paid',
        'paid_at': DateTime.now().toIso8601String(),
        'receipt_number': 'RCPT-${DateTime.now().millisecondsSinceEpoch}',
      }).eq('id', row['id'] as String);
      await AuditService.log(
        module: 'fees',
        action: 'mark_paid',
        newValue: {'invoice_id': row['invoice_id']},
      );
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete fee record?'),
        content: Text('This removes invoice ${row['invoice_id']} permanently.'),
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
      await supabase
          .from(SupabaseConfig.feePaymentsTable)
          .delete()
          .eq('id', row['id'] as String);
      await AuditService.log(
          module: 'fees', action: 'delete', oldValue: {'invoice_id': row['invoice_id']});
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _sendReminder(Map<String, dynamic> row) async {
    final phone = _studentPhone(row);
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No phone number on file for this student')));
      return;
    }
    final amountPaise = row['amount_paise'] as int;
    final message = NotificationService.compose(
      row['status'] == 'paid' ? NotificationTrigger.feePayment : NotificationTrigger.feeReminder,
      studentName: _studentName(row),
      amountDisplay: '₹${(amountPaise / 100).toStringAsFixed(2)}',
    );
    await NotificationService.sendViaWhatsApp(
      context: context,
      phone: phone,
      message: message,
      trigger: row['status'] == 'paid' ? NotificationTrigger.feePayment : NotificationTrigger.feeReminder,
      studentId: row['student_id'] as String,
    );
  }

  Future<void> _shareReceipt(Map<String, dynamic> row) async {
    try {
      await ReceiptService.shareReceipt(
        studentName: _studentName(row),
        invoiceId: row['invoice_id'] as String,
        amountPaise: row['amount_paise'] as int,
        status: row['status'] as String,
        paidAt: row['paid_at'] != null ? DateTime.parse(row['paid_at'] as String) : null,
        dueDate: row['due_date'] != null ? DateTime.parse(row['due_date'] as String) : null,
        description: row['description'] as String?,
        paymentMode: row['payment_mode'] as String?,
        transactionRef: row['transaction_ref'] as String?,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Widget _buildPaymentsTab() {
    final filtered = _filteredPayments;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in const ['all', 'pending', 'paid', 'overdue', 'waived'])
                  ChoiceChip(
                    label: Text(s.toUpperCase()),
                    selected: _statusFilter == s,
                    onSelected: (_) => setState(() => _statusFilter = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No fee records'))
                : RefreshIndicator(
                    onRefresh: _loadAll,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final row = filtered[i];
                        final status = row['status'] as String;
                        final (color, icon) = _statusStyle(status);
                        final amount =
                            '₹${((row['amount_paise'] as int) / 100).toStringAsFixed(2)}';
                        return Card(
                          child: ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(_studentName(row)),
                            subtitle: Text(
                              '${row['invoice_id']} · ${_feeTypeName(row['fee_type_id'] as String?)} · ${row['description'] ?? 'Fee payment'}\n'
                              'Due: ${row['due_date'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(row['due_date'] as String)) : '—'}',
                            ),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(amount,
                                    style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (status != 'paid')
                                      IconButton(
                                        icon: const Icon(Icons.check_circle_outline, size: 20),
                                        tooltip: 'Mark paid',
                                        onPressed: () => _markPaid(row),
                                      ),
                                    if (status == 'pending' || status == 'overdue')
                                      IconButton(
                                        icon: const Icon(Icons.chat_outlined, size: 20, color: Colors.green),
                                        tooltip: 'Send WhatsApp reminder',
                                        onPressed: () => _sendReminder(row),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.share_outlined, size: 20),
                                      tooltip: 'Share receipt',
                                      onPressed: status == 'paid' ? () => _shareReceipt(row) : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      onPressed: () => _openPaymentDialog(existing: row),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      onPressed: () => _confirmDelete(row),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_fee',
        onPressed: () => _openPaymentDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Fee Record'),
      ),
    );
  }

  Widget _buildReportsTab() {
    final totalCollected = _payments
        .where((p) => p['status'] == 'paid')
        .fold<int>(0, (sum, p) => sum + (p['amount_paise'] as int));
    final totalPending = _payments
        .where((p) => p['status'] == 'pending' || p['status'] == 'overdue')
        .fold<int>(0, (sum, p) => sum + (p['amount_paise'] as int));
    final countsByStatus = <String, int>{};
    for (final p in _payments) {
      final s = p['status'] as String;
      countsByStatus[s] = (countsByStatus[s] ?? 0) + 1;
    }
    final pendingList = _payments
        .where((p) => p['status'] == 'pending' || p['status'] == 'overdue')
        .toList();

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryCard('Collected', totalCollected, Colors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard('Pending / Overdue', totalPending, Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_payments.isNotEmpty) ...[
            Text('Status breakdown',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: countsByStatus.entries.map((e) {
                final (color, _) = _statusStyle(e.key);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${e.key.toUpperCase()}: ${e.value}'),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
          Text('Pending & overdue',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (pendingList.isEmpty)
            const Text('Nothing outstanding')
          else
            ...pendingList.map((row) {
              final (color, icon) = _statusStyle(row['status'] as String);
              return Card(
                child: ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(_studentName(row)),
                  subtitle: Text(row['invoice_id'] as String),
                  trailing: Text(
                    '₹${((row['amount_paise'] as int) / 100).toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, int amountPaise, Color color) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('₹${(amountPaise / 100).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPayments() async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'fee_payments',
        headers: const [
          'Student',
          'Invoice',
          'Fee Type',
          'Description',
          'Amount',
          'Status',
          'Due Date',
          'Paid At',
        ],
        rows: _filteredPayments
            .map((row) => [
                  _studentName(row),
                  row['invoice_id'],
                  _feeTypeName(row['fee_type_id'] as String?),
                  row['description'] ?? '',
                  ((row['amount_paise'] as int) / 100).toStringAsFixed(2),
                  row['status'],
                  row['due_date'] != null
                      ? DateFormat('yyyy-MM-dd').format(DateTime.parse(row['due_date'] as String))
                      : '',
                  row['paid_at'] != null
                      ? DateFormat('yyyy-MM-dd').format(DateTime.parse(row['paid_at'] as String))
                      : '',
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
        title: const Text('Fee Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Export payments as Excel',
            onPressed: _filteredPayments.isEmpty ? null : _exportPayments,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'Payments'), Tab(text: 'Reports')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildPaymentsTab(), _buildReportsTab()],
            ),
    );
  }
}
