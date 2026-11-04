import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/expense_category.dart';
import 'package:school_management_app/services/app_settings_service.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/services/expense_document_service.dart';
import 'package:school_management_app/services/expense_pdf_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

const _paymentModes = ['Cash', 'UPI', 'Bank', 'Cheque'];

enum _ReportPeriod { daily, weekly, monthly, yearly }

String _money(int? paise) => '₹${((paise ?? 0) / 100).toStringAsFixed(2)}';

/// Module: Expense & Maintenance Management — Dashboard/Expenses/Reports,
/// built the same way fee_management_screen.dart is (status ChoiceChips,
/// a create/edit dialog, per-row action icons, a Reports tab with charts and
/// Excel/PDF export) since that's the closest existing analogue: a ledger of
/// money movements with an approval-ish status lifecycle.
class ExpenseManagementScreen extends StatefulWidget {
  const ExpenseManagementScreen({super.key});

  @override
  State<ExpenseManagementScreen> createState() => _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<Map<String, dynamic>> _expenses = [];
  List<ExpenseCategory> _categories = [];
  List<Map<String, dynamic>> _repairs = [];
  int _approvalThresholdPaise = 500000;
  String _statusFilter = 'all';
  String _query = '';
  _ReportPeriod _reportPeriod = _ReportPeriod.monthly;
  DateTime _reportAnchor = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        supabase
            .from('expenses')
            .select('*, expense_categories(name)')
            .isFilter('deleted_at', null)
            .order('expense_date', ascending: false),
        supabase.from('expense_categories').select().order('name'),
        supabase
            .from('repair_requests')
            .select('id, location, description, actual_cost_paise, estimated_cost_paise, status')
            .isFilter('deleted_at', null),
        AppSettingsService.expenseApprovalThresholdPaise(),
      ]);
      setState(() {
        _expenses = List<Map<String, dynamic>>.from(results[0] as List);
        _categories = (results[1] as List)
            .map((e) => ExpenseCategory.fromJson(e as Map<String, dynamic>))
            .toList();
        _repairs = List<Map<String, dynamic>>.from(results[2] as List);
        _approvalThresholdPaise = results[3] as int;
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

  String _categoryName(Map<String, dynamic> row) =>
      (row['expense_categories'] as Map?)?['name'] as String? ?? '—';

  List<Map<String, dynamic>> get _filteredExpenses {
    var rows = _expenses;
    if (_statusFilter != 'all') {
      rows = rows.where((r) => r['status'] == _statusFilter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      rows = rows.where((r) {
        return (r['description'] as String? ?? '').toLowerCase().contains(q) ||
            (r['vendor_name'] as String? ?? '').toLowerCase().contains(q) ||
            (r['bill_number'] as String? ?? '').toLowerCase().contains(q) ||
            _categoryName(r).toLowerCase().contains(q) ||
            (r['expense_date'] as String? ?? '').contains(q);
      }).toList();
    }
    return rows;
  }

  (Color, IconData) _statusStyle(String status) {
    switch (status) {
      case 'paid':
        return (Colors.green, Icons.check_circle);
      case 'approved':
        return (Colors.blue, Icons.thumb_up_alt_outlined);
      default:
        return (Colors.orange, Icons.schedule);
    }
  }

  /// Returns the new category's id so the caller can pre-select it, or null
  /// if the admin cancelled.
  Future<String?> _addCategoryDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final newId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Expense Category'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              try {
                final created = await supabase
                    .from('expense_categories')
                    .insert({'name': name})
                    .select()
                    .single();
                if (dialogContext.mounted) Navigator.pop(dialogContext, created['id'] as String);
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
    );
    if (newId != null) {
      final rows = await supabase.from('expense_categories').select().order('name');
      setState(() {
        _categories = (rows as List)
            .map((e) => ExpenseCategory.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    }
    return newId;
  }

  Future<void> _openExpenseDialog({Map<String, dynamic>? existing}) async {
    final formKey = GlobalKey<FormState>();
    String? categoryId = existing?['category_id'] as String? ??
        (_categories.isNotEmpty ? _categories.first.id : null);
    final descCtrl = TextEditingController(text: existing?['description'] as String? ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? ((existing['amount_paise'] as int) / 100).toStringAsFixed(2) : '');
    final vendorCtrl = TextEditingController(text: existing?['vendor_name'] as String? ?? '');
    final billCtrl = TextEditingController(text: existing?['bill_number'] as String? ?? '');
    final remarksCtrl = TextEditingController(text: existing?['remarks'] as String? ?? '');
    String paymentMode = existing?['payment_mode'] as String? ?? _paymentModes.first;
    DateTime expenseDate = existing?['expense_date'] != null
        ? DateTime.parse(existing!['expense_date'] as String)
        : DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Record Expense' : 'Edit Expense'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: categoryId,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: _categories
                              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (v) => setDialogState(() => categoryId = v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Add category',
                        onPressed: () async {
                          final newId = await _addCategoryDialog(dialogContext);
                          if (newId != null) setDialogState(() => categoryId = newId);
                        },
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date'),
                    subtitle: Text(DateFormat('d MMM yyyy').format(expenseDate)),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: expenseDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDialogState(() => expenseDate = picked);
                    },
                  ),
                  TextFormField(
                    controller: vendorCtrl,
                    decoration: const InputDecoration(labelText: 'Vendor / person paid (optional)'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMode,
                    decoration: const InputDecoration(labelText: 'Payment mode'),
                    items: _paymentModes
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => paymentMode = v!),
                  ),
                  TextFormField(
                    controller: billCtrl,
                    decoration: const InputDecoration(labelText: 'Bill/receipt number (optional)'),
                  ),
                  TextFormField(
                    controller: remarksCtrl,
                    decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                    maxLines: 2,
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        existing['receipt_url'] != null ? Icons.check_circle : Icons.upload_file_outlined,
                        color: existing['receipt_url'] != null ? Colors.green : null,
                      ),
                      title: Text(existing['receipt_url'] != null ? 'Receipt uploaded' : 'No receipt uploaded'),
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            final path = await ExpenseDocumentService.pickAndUpload(
                              recordId: existing['id'] as String,
                              docType: 'receipt',
                            );
                            if (path != null) {
                              await supabase.from('expenses').update({'receipt_url': path}).eq(
                                  'id', existing['id'] as String);
                              existing['receipt_url'] = path;
                              setDialogState(() {});
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext)
                                  .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                            }
                          }
                        },
                        child: Text(existing['receipt_url'] != null ? 'Replace' : 'Upload'),
                      ),
                    ),
                  ],
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
                    'category_id': categoryId,
                    'description': descCtrl.text.trim(),
                    'amount_paise': (double.parse(amountCtrl.text) * 100).round(),
                    'expense_date': expenseDate.toIso8601String().substring(0, 10),
                    'vendor_name': vendorCtrl.text.trim().isEmpty ? null : vendorCtrl.text.trim(),
                    'payment_mode': paymentMode,
                    'bill_number': billCtrl.text.trim().isEmpty ? null : billCtrl.text.trim(),
                    'remarks': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
                  };
                  if (existing == null) {
                    await supabase.from('expenses').insert({
                      ...payload,
                      'status': 'pending',
                      'created_by': supabase.auth.currentUser?.id,
                    });
                  } else {
                    await supabase.from('expenses').update(payload).eq('id', existing['id'] as String);
                  }
                  await AuditService.log(
                    module: 'expenses',
                    action: existing == null ? 'create' : 'update',
                    oldValue: existing,
                    newValue: payload,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _loadAll();
                } catch (e) {
                  if (dialogContext.mounted) {
                    final message = friendlyErrorMessage(e) == 'This already exists.'
                        ? 'An expense with this bill number already exists.'
                        : friendlyErrorMessage(e);
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    try {
      final payload = <String, dynamic>{'status': status};
      if (status == 'approved') {
        payload['approved_by'] = supabase.auth.currentUser?.id;
        payload['approved_at'] = DateTime.now().toIso8601String();
      }
      await supabase.from('expenses').update(payload).eq('id', row['id'] as String);
      await AuditService.log(module: 'expenses', action: status, newValue: {'id': row['id']});
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _cancelExpense(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this expense?'),
        content: const Text(
            'It will be removed from the active list but kept for audit history — financial records are never permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Expense'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.from('expenses').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': supabase.auth.currentUser?.id,
      }).eq('id', row['id'] as String);
      await AuditService.log(module: 'expenses', action: 'cancel', oldValue: row);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _viewReceipt(String path) async {
    try {
      final url = await ExpenseDocumentService.signedUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  // ── Dashboard tab ───────────────────────────────────────────────────────
  Widget _buildDashboardTab() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final monthPrefix = DateFormat('yyyy-MM').format(DateTime.now());
    final todayTotal = _expenses
        .where((e) => e['expense_date'] == today)
        .fold<int>(0, (sum, e) => sum + (e['amount_paise'] as int));
    final monthTotal = _expenses
        .where((e) => (e['expense_date'] as String).startsWith(monthPrefix))
        .fold<int>(0, (sum, e) => sum + (e['amount_paise'] as int));
    final pending = _expenses.where((e) => e['status'] == 'pending').toList();
    final pendingTotal = pending.fold<int>(0, (sum, e) => sum + (e['amount_paise'] as int));
    final repairCost = _repairs.fold<int>(
        0, (sum, r) => sum + ((r['actual_cost_paise'] as int?) ?? 0));

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _statCard("Today's Expense", _money(todayTotal), Colors.blue),
              _statCard('This Month', _money(monthTotal), Colors.teal),
              _statCard('Pending (${pending.length})', _money(pendingTotal), Colors.orange),
              _statCard('Total Repair Cost', _money(repairCost), Colors.purple),
            ],
          ),
          const SizedBox(height: 24),
          Text('Recent expenses',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_expenses.isEmpty)
            const Text('No expenses recorded yet')
          else
            ..._expenses.take(5).map((e) {
              final (color, icon) = _statusStyle(e['status'] as String);
              return Card(
                child: ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(e['description'] as String),
                  subtitle: Text('${_categoryName(e)} · ${e['expense_date']}'),
                  trailing: Text(_money(e['amount_paise'] as int),
                      style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600), maxLines: 1),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ── Expenses tab ────────────────────────────────────────────────────────
  Widget _buildExpensesTab() {
    final filtered = _filteredExpenses;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by date, category, vendor, or bill number...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in const ['all', 'pending', 'approved', 'paid'])
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
                ? const Center(child: Text('No expenses found'))
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
                        final needsApproval =
                            (row['amount_paise'] as int) > _approvalThresholdPaise;
                        return Card(
                          child: ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(row['description'] as String),
                            subtitle: Text(
                              '${_categoryName(row)} · ${row['vendor_name'] ?? 'No vendor'} · ${row['payment_mode']}\n'
                              '${row['expense_date']}${row['bill_number'] != null ? ' · Bill: ${row['bill_number']}' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_money(row['amount_paise'] as int),
                                    style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (row['receipt_url'] != null)
                                      IconButton(
                                        icon: const Icon(Icons.receipt_long_outlined, size: 20),
                                        tooltip: 'View receipt',
                                        onPressed: () => _viewReceipt(row['receipt_url'] as String),
                                      ),
                                    if (status == 'pending' && needsApproval)
                                      IconButton(
                                        icon: const Icon(Icons.thumb_up_alt_outlined, size: 20, color: Colors.blue),
                                        tooltip: 'Approve',
                                        onPressed: () => _setStatus(row, 'approved'),
                                      ),
                                    if (status == 'pending' && !needsApproval)
                                      IconButton(
                                        icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
                                        tooltip: 'Mark paid',
                                        onPressed: () => _setStatus(row, 'paid'),
                                      ),
                                    if (status == 'approved')
                                      IconButton(
                                        icon: const Icon(Icons.check_circle_outline, size: 20, color: Colors.green),
                                        tooltip: 'Mark paid',
                                        onPressed: () => _setStatus(row, 'paid'),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      onPressed: () => _openExpenseDialog(existing: row),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.red),
                                      onPressed: () => _cancelExpense(row),
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
        heroTag: 'add_expense',
        onPressed: () => _openExpenseDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Expense'),
      ),
    );
  }

  // ── Reports tab ─────────────────────────────────────────────────────────
  (DateTime, DateTime) get _reportRange {
    switch (_reportPeriod) {
      case _ReportPeriod.daily:
        final start = DateTime(_reportAnchor.year, _reportAnchor.month, _reportAnchor.day);
        return (start, start.add(const Duration(days: 1)));
      case _ReportPeriod.weekly:
        final start = DateTime(_reportAnchor.year, _reportAnchor.month, _reportAnchor.day)
            .subtract(Duration(days: _reportAnchor.weekday - 1));
        return (start, start.add(const Duration(days: 7)));
      case _ReportPeriod.monthly:
        final start = DateTime(_reportAnchor.year, _reportAnchor.month, 1);
        return (start, DateTime(_reportAnchor.year, _reportAnchor.month + 1, 1));
      case _ReportPeriod.yearly:
        return (DateTime(_reportAnchor.year, 1, 1), DateTime(_reportAnchor.year + 1, 1, 1));
    }
  }

  String get _reportRangeLabel {
    final (start, end) = _reportRange;
    switch (_reportPeriod) {
      case _ReportPeriod.daily:
        return DateFormat('EEE, d MMM yyyy').format(start);
      case _ReportPeriod.weekly:
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end.subtract(const Duration(days: 1)))}';
      case _ReportPeriod.monthly:
        return DateFormat('MMMM yyyy').format(start);
      case _ReportPeriod.yearly:
        return start.year.toString();
    }
  }

  void _shiftReportAnchor(int direction) {
    setState(() {
      switch (_reportPeriod) {
        case _ReportPeriod.daily:
          _reportAnchor = _reportAnchor.add(Duration(days: direction));
          break;
        case _ReportPeriod.weekly:
          _reportAnchor = _reportAnchor.add(Duration(days: 7 * direction));
          break;
        case _ReportPeriod.monthly:
          _reportAnchor = DateTime(_reportAnchor.year, _reportAnchor.month + direction, 1);
          break;
        case _ReportPeriod.yearly:
          _reportAnchor = DateTime(_reportAnchor.year + direction, 1, 1);
          break;
      }
    });
  }

  List<Map<String, dynamic>> get _periodExpenses {
    final (start, end) = _reportRange;
    return _expenses.where((e) {
      final date = DateTime.parse(e['expense_date'] as String);
      return !date.isBefore(start) && date.isBefore(end);
    }).toList();
  }

  Map<String, int> _groupTotals(String Function(Map<String, dynamic>) keyOf) {
    final totals = <String, int>{};
    for (final e in _periodExpenses) {
      final key = keyOf(e);
      totals[key] = (totals[key] ?? 0) + (e['amount_paise'] as int);
    }
    return totals;
  }

  /// Expenses logged against a specific repair job (via expenses.repair_id,
  /// set from repair_detail_screen.dart's "Log payment as expense"),
  /// grouped by that repair for the "Repair-wise expenses" report.
  Map<String, int> get _byRepair {
    final totals = <String, int>{};
    for (final e in _periodExpenses) {
      final repairId = e['repair_id'] as String?;
      if (repairId == null) continue;
      final repair = _repairs.firstWhere((r) => r['id'] == repairId, orElse: () => const {});
      final label = repair.isEmpty
          ? 'Repair'
          : '${repair['location']} — ${(repair['description'] as String).length > 24 ? '${(repair['description'] as String).substring(0, 24)}…' : repair['description']}';
      totals[label] = (totals[label] ?? 0) + (e['amount_paise'] as int);
    }
    return totals;
  }

  Future<void> _exportExcel() async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'expense_report',
        headers: const ['Date', 'Category', 'Description', 'Amount', 'Vendor', 'Payment Mode', 'Bill No.', 'Status'],
        rows: _periodExpenses
            .map((e) => [
                  e['expense_date'],
                  _categoryName(e),
                  e['description'],
                  ((e['amount_paise'] as int) / 100).toStringAsFixed(2),
                  e['vendor_name'] ?? '',
                  e['payment_mode'],
                  e['bill_number'] ?? '',
                  e['status'],
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

  Future<void> _exportPdf() async {
    try {
      await ExpensePdfService.exportTable(
        title: 'Expense Report',
        fileBaseName: 'expense_report',
        headers: const ['Date', 'Category', 'Description', 'Amount', 'Status'],
        rows: _periodExpenses
            .map((e) => [
                  e['expense_date'] as String,
                  _categoryName(e),
                  e['description'] as String,
                  _money(e['amount_paise'] as int),
                  e['status'] as String,
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

  Widget _buildReportsTab() {
    final periodExpenses = _periodExpenses;
    final totalExpenditure = periodExpenses.fold<int>(0, (sum, e) => sum + (e['amount_paise'] as int));
    final paidTotal = periodExpenses
        .where((e) => e['status'] == 'paid')
        .fold<int>(0, (sum, e) => sum + (e['amount_paise'] as int));
    final approvedOrPaid = periodExpenses.where((e) => e['status'] != 'pending').length;
    final periodPendingCount = periodExpenses.length - approvedOrPaid;
    final periodPendingTotal = periodExpenses
        .where((e) => e['status'] == 'pending')
        .fold<int>(0, (s, e) => s + (e['amount_paise'] as int));
    // Outstanding payments are shown all-time, not period-filtered — a bill
    // entered last month that's still unpaid is still owed today.
    final allTimePending = _expenses.where((e) => e['status'] == 'pending').toList();

    final byCategory = _groupTotals(_categoryName);
    final byVendor = _groupTotals((e) => e['vendor_name'] as String? ?? 'Unspecified');
    final byPaymentMode = _groupTotals((e) => e['payment_mode'] as String);
    final byRepair = _byRepair;

    final estimatedRepairTotal =
        _repairs.fold<int>(0, (sum, r) => sum + ((r['estimated_cost_paise'] as int?) ?? 0));
    final actualRepairTotal =
        _repairs.fold<int>(0, (sum, r) => sum + ((r['actual_cost_paise'] as int?) ?? 0));

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final p in _ReportPeriod.values)
                ChoiceChip(
                  label: Text(p.name[0].toUpperCase() + p.name.substring(1)),
                  selected: _reportPeriod == p,
                  onSelected: (_) => setState(() => _reportPeriod = p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftReportAnchor(-1)),
              Text(_reportRangeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftReportAnchor(1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: periodExpenses.isEmpty ? null : _exportExcel,
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Export Excel'),
              )),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(
                onPressed: periodExpenses.isEmpty ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export PDF'),
              )),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _summaryCard('Total Expenditure', totalExpenditure, Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard('Paid', paidTotal, Colors.green)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _summaryCard('Approved / Paid ($approvedOrPaid)', paidTotal, Colors.teal)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard('Unapproved ($periodPendingCount)', periodPendingTotal, Colors.orange)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _summaryCard('Estimated Repair Cost', estimatedRepairTotal, Colors.indigo)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard('Actual Repair Cost', actualRepairTotal, Colors.purple)),
            ],
          ),
          const SizedBox(height: 24),
          _breakdownSection('Category-wise expenses', byCategory),
          _breakdownSection('Vendor-wise expenses', byVendor),
          _breakdownSection('Payment-mode-wise expenses', byPaymentMode),
          _breakdownSection('Repair-wise expenses', byRepair),
          const SizedBox(height: 12),
          Text('Pending payments (all time)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (allTimePending.isEmpty)
            const Text('Nothing pending')
          else
            ...allTimePending.map((e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule, color: Colors.orange),
                    title: Text(e['description'] as String),
                    subtitle: Text('${_categoryName(e)} · ${e['expense_date']}'),
                    trailing: Text(_money(e['amount_paise'] as int),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ),
                )),
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
            Text(_money(amountPaise), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _breakdownSection(String title, Map<String, int> totals) {
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxY = entries.isEmpty ? 1.0 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text('No data yet')
          else
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.2,
                  barGroups: [
                    for (var i = 0; i < entries.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(toY: entries[i].value.toDouble(), color: Theme.of(context).colorScheme.primary, width: 20),
                      ]),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(entries[i].key,
                                style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense & Maintenance'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'Dashboard'), Tab(text: 'Expenses'), Tab(text: 'Reports')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildDashboardTab(), _buildExpensesTab(), _buildReportsTab()],
            ),
    );
  }
}
