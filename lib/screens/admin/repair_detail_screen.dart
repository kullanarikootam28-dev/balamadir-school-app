import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/repair_request.dart';
import 'package:school_management_app/screens/admin/repair_management_screen.dart'
    show kRepairLocations, kRepairCategories, repairStatusColor;
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/expense_document_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

const _docTypeLabels = {
  'quotation': 'Quotation',
  'bill': 'Bill',
  'before_photo': 'Before-repair photo',
  'after_photo': 'After-repair photo',
};

/// Full repair lifecycle editor: location/category/description, cost
/// tracking (estimated/actual/advance, with remaining payment computed),
/// document uploads, and the status walk from Reported through
/// Completed/Cancelled — mirrors teacher_record_detail_screen.dart's
/// load-edit-save shape.
class RepairDetailScreen extends StatefulWidget {
  const RepairDetailScreen({super.key, required this.repair});
  final RepairRequest repair;

  @override
  State<RepairDetailScreen> createState() => _RepairDetailScreenState();
}

class _RepairDetailScreenState extends State<RepairDetailScreen> {
  late RepairRequest _repair;
  bool _saving = false;

  late String _location;
  late String _category;
  final _descCtrl = TextEditingController();
  final _responsibleCtrl = TextEditingController();
  final _estimateCtrl = TextEditingController();
  final _actualCtrl = TextEditingController();
  final _advanceCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  late RepairStatus _status;
  DateTime? _completionDate;

  @override
  void initState() {
    super.initState();
    _repair = widget.repair;
    _location = kRepairLocations.contains(_repair.location) ? _repair.location : kRepairLocations.last;
    _category = kRepairCategories.contains(_repair.category) ? _repair.category : kRepairCategories.last;
    _descCtrl.text = _repair.description;
    _responsibleCtrl.text = _repair.responsiblePerson ?? '';
    _estimateCtrl.text =
        _repair.estimatedCostPaise != null ? (_repair.estimatedCostPaise! / 100).toStringAsFixed(2) : '';
    _actualCtrl.text = _repair.actualCostPaise != null ? (_repair.actualCostPaise! / 100).toStringAsFixed(2) : '';
    _advanceCtrl.text =
        _repair.advancePaidPaise != null ? (_repair.advancePaidPaise! / 100).toStringAsFixed(2) : '';
    _remarksCtrl.text = _repair.remarks ?? '';
    _status = _repair.status;
    _completionDate = _repair.completionDate;
  }

  @override
  void dispose() {
    for (final c in [_descCtrl, _responsibleCtrl, _estimateCtrl, _actualCtrl, _advanceCtrl, _remarksCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _parsePaise(String text) =>
      text.trim().isEmpty ? null : (double.parse(text.trim()) * 100).round();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'location': _location,
        'category': _category,
        'description': _descCtrl.text.trim(),
        'responsible_person': _responsibleCtrl.text.trim().isEmpty ? null : _responsibleCtrl.text.trim(),
        'estimated_cost_paise': _parsePaise(_estimateCtrl.text),
        'actual_cost_paise': _parsePaise(_actualCtrl.text),
        'advance_paid_paise': _parsePaise(_advanceCtrl.text),
        'status': repairStatusToJson(_status),
        'completion_date': _completionDate?.toIso8601String().substring(0, 10),
        'remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      };
      await supabase.from('repair_requests').update(payload).eq('id', _repair.id);
      await AuditService.log(
        module: 'repairs',
        action: 'update',
        oldValue: _repair.toJson(),
        newValue: payload,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
        setState(() {
          _repair = RepairRequest.fromJson({..._repair.toJson(), ...payload, 'id': _repair.id});
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadDoc(String docType) async {
    try {
      final path = await ExpenseDocumentService.pickAndUpload(recordId: _repair.id, docType: docType);
      if (path == null) return;
      final column = '${docType}_url';
      await supabase.from('repair_requests').update({column: path}).eq('id', _repair.id);
      setState(() {
        _repair = RepairRequest.fromJson({..._repair.toJson(), column: path, 'id': _repair.id});
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${_docTypeLabels[docType]} uploaded')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _viewDoc(String path) async {
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

  Future<void> _cancelRepair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this repair request?'),
        content: const Text('It will be removed from the active list but kept for audit history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.from('repair_requests').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': supabase.auth.currentUser?.id,
      }).eq('id', _repair.id);
      await AuditService.log(module: 'repairs', action: 'cancel', oldValue: _repair.toJson());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _logPaymentAsExpense() async {
    final actualPaise = _parsePaise(_actualCtrl.text);
    if (actualPaise == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an actual cost before logging a payment')));
      return;
    }
    try {
      final category = await supabase
          .from('expense_categories')
          .select('id')
          .eq('name', 'Repair')
          .maybeSingle();
      final payload = {
        'category_id': category?['id'],
        'description': 'Repair: ${_repair.location} — ${_repair.description}',
        'amount_paise': actualPaise,
        'expense_date': DateTime.now().toIso8601String().substring(0, 10),
        'vendor_name': _responsibleCtrl.text.trim().isEmpty ? null : _responsibleCtrl.text.trim(),
        'payment_mode': 'Cash',
        'status': 'pending',
        'repair_id': _repair.id,
        'created_by': supabase.auth.currentUser?.id,
      };
      await supabase.from('expenses').insert(payload);
      await AuditService.log(module: 'expenses', action: 'create_from_repair', newValue: payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logged as a pending expense — approve/mark paid from Expense Management')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _docTile(String docType, String? url) => Card(
        child: ListTile(
          leading: Icon(
            url != null ? Icons.check_circle : Icons.upload_file_outlined,
            color: url != null ? Colors.green : null,
          ),
          title: Text(_docTypeLabels[docType]!),
          subtitle: Text(url != null ? 'Uploaded' : 'Not uploaded'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (url != null)
                IconButton(
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: () => _viewDoc(url),
                ),
              TextButton(
                onPressed: () => _uploadDoc(docType),
                child: Text(url != null ? 'Replace' : 'Upload'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final remaining = _repair.remainingPaise;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_repair.location} · ${_repair.category}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cancel_outlined),
            tooltip: 'Cancel request',
            onPressed: _cancelRepair,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _location,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: kRepairLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (v) => setState(() => _location = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: kRepairCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Problem description', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Text('Reported ${DateFormat('d MMM yyyy').format(_repair.reportedDate)}',
              style: Theme.of(context).textTheme.bodySmall),
          _sectionTitle('Status'),
          DropdownButtonFormField<RepairStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: RepairStatus.values
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(repairStatusLabel(s), style: TextStyle(color: repairStatusColor(s))),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _status = v!),
          ),
          if (_status == RepairStatus.completed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Completion date'),
              subtitle: Text(_completionDate != null
                  ? DateFormat('d MMM yyyy').format(_completionDate!)
                  : 'Not set'),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _completionDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _completionDate = picked);
              },
            ),
          _sectionTitle('Vendor & cost'),
          TextField(
            controller: _responsibleCtrl,
            decoration: const InputDecoration(labelText: 'Responsible person/vendor', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _estimateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Estimated cost (₹)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _actualCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Actual cost (₹)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _advanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Advance paid (₹)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Remaining payment', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    remaining != null ? '₹${(remaining / 100).toStringAsFixed(2)}' : '—',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _logPaymentAsExpense,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Log payment as expense'),
          ),
          _sectionTitle('Documents'),
          _docTile('quotation', _repair.quotationUrl),
          _docTile('bill', _repair.billUrl),
          _docTile('before_photo', _repair.beforePhotoUrl),
          _docTile('after_photo', _repair.afterPhotoUrl),
          _sectionTitle('Remarks'),
          TextField(
            controller: _remarksCtrl,
            decoration: const InputDecoration(labelText: 'Remarks (optional)', border: OutlineInputBorder()),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
