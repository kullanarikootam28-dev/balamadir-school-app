import 'package:flutter/material.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Fully anonymous — no student id is ever attached to a submitted
/// complaint, so there's nothing here for even an admin to trace back.
class ComplaintBoxScreen extends StatefulWidget {
  const ComplaintBoxScreen({super.key});

  @override
  State<ComplaintBoxScreen> createState() => _ComplaintBoxScreenState();
}

class _ComplaintBoxScreenState extends State<ComplaintBoxScreen> {
  final _messageCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _submitting = true;
      _submitted = false;
    });
    try {
      await supabase.from('complaints').insert({'message': message});
      _messageCtrl.clear();
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint Box')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Your complaint is submitted anonymously — nothing links it back to you.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _messageCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'What would you like to report?',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (_submitted) ...[
                const SizedBox(height: 12),
                const Text('Submitted. Thank you.',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
