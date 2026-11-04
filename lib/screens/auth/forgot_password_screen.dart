import 'package:flutter/material.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/email_check.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Emails a password-reset link (Supabase's default template works as-is —
/// no dashboard edits needed). Tapping it on this device reopens the app via
/// the registered deep link, Supabase exchanges it for a temporary recovery
/// session, and app.dart's redirect logic (driven by [PasswordRecoveryFlag])
/// routes straight to SetNewPasswordScreen instead of the normal home
/// redirect.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
  bool _linkSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    final suggestion = emailTypoSuggestion(email);
    if (suggestion != null) {
      setState(() => _error = 'Check the email — did you mean $suggestion? '
          'A reset link can\'t be delivered to "$email".');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.schoolapp://reset-callback/',
      );
      if (mounted) setState(() => _linkSent = true);
    } catch (e) {
      setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_reset_outlined, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  _linkSent
                      ? 'Check ${_emailCtrl.text.trim()} and tap the reset link on this device'
                      : "We'll email you a link to reset your password",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  enabled: !_linkSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                if (!_linkSent)
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _sendLink,
                      style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Send Reset Link'),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _linkSent = false;
                              _error = null;
                            }),
                    child: const Text('Use a different email'),
                  ),
                const SizedBox(height: 24),
                Text(
                  "Didn't get the email? The school office can set a new password for you "
                  'from User Management — ask them directly.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
