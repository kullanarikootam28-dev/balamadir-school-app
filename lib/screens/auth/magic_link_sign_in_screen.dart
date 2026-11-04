import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/main.dart';

/// Passwordless sign-in: emails a tappable link (no SMS/WhatsApp provider
/// needed, and no dashboard template edits either — Supabase's default
/// "Magic Link" email already works as-is). Tapping the link on this device
/// reopens the app via the `io.supabase.schoolapp` deep link already
/// registered in AndroidManifest.xml; supabase_flutter exchanges it for a
/// session automatically, and the router's redirect logic takes it from
/// there — see app.dart.
class MagicLinkSignInScreen extends StatefulWidget {
  const MagicLinkSignInScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<MagicLinkSignInScreen> createState() => _MagicLinkSignInScreenState();
}

class _MagicLinkSignInScreenState extends State<MagicLinkSignInScreen> {
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
        emailRedirectTo: 'io.supabase.schoolapp://login-callback/',
      );
      if (mounted) setState(() => _linkSent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with magic link')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  _linkSent
                      ? 'Check ${_emailCtrl.text.trim()} and tap the sign-in link on this device'
                      : "We'll email you a link — tap it on this device to sign in, no password needed",
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
                          : const Text('Send Magic Link'),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
