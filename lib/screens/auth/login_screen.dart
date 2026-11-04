import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/clock_check.dart';
import 'package:school_management_app/utils/email_check.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Key under which the last-signed-in email is remembered locally, so
/// returning users don't have to retype it — the password itself is never
/// persisted here (Supabase's own session storage handles staying logged
/// in; this is purely a "don't make me retype my email" convenience for
/// when they do land back on this screen).
const _lastEmailPrefsKey = 'last_login_email';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  int _failedAttempts = 0;
  String? _emailSuggestion;

  @override
  void initState() {
    super.initState();
    // A new email means a new login attempt context, so past failures on a
    // different account shouldn't keep the recovery options showing.
    _emailCtrl.addListener(() {
      if (_failedAttempts != 0) setState(() => _failedAttempts = 0);
      final suggestion = emailTypoSuggestion(_emailCtrl.text);
      if (suggestion != _emailSuggestion) setState(() => _emailSuggestion = suggestion);
    });
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_lastEmailPrefsKey);
    if (saved != null && mounted) {
      setState(() => _emailCtrl.text = saved);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _loading = true);
    try {
      // A wrong clock/time zone makes sign-in fail silently (see
      // ClockCheck) — catch it first and say exactly how to fix it.
      if (!await ClockCheck.ensureClockIsCorrect(context)) return;

      final email = _emailCtrl.text.trim();
      // Don't sit on the login screen forever if something on this PC
      // (firewall, antivirus, proxy) silently blocks the connection.
      await supabase.auth
          .signInWithPassword(email: email, password: _passCtrl.text.trim())
          .timeout(const Duration(seconds: 30));
      (await SharedPreferences.getInstance()).setString(_lastEmailPrefsKey, email);
      if (mounted) context.go('/');
    } catch (e) {
      if (e is AuthException) setState(() => _failedAttempts++);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRecovery(String route) {
    ScaffoldMessenger.of(context).clearSnackBars();
    context.push(route, extra: _emailCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo.png', width: 96, height: 96),
                  const SizedBox(height: 16),
                  Text('Balamandir School App',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Sign in to continue',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    validator: (v) =>
                        v == null || !v.contains('@') ? 'Enter a valid email' : null,
                  ),
                  if (_emailSuggestion != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.spellcheck, size: 18),
                        label: Text('Did you mean $_emailSuggestion?'),
                        onPressed: () => _emailCtrl.text = _emailSuggestion!,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.length < 6 ? 'Min 6 characters' : null,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _signIn,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Sign In',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  if (_failedAttempts >= 3) ...[
                    const SizedBox(height: 20),
                    Text(
                      "Having trouble signing in?",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _loading ? null : () => _openRecovery('/forgot-password'),
                          child: const Text('Forgot password?'),
                        ),
                        TextButton(
                          onPressed: _loading ? null : () => _openRecovery('/magic-link-sign-in'),
                          child: const Text('Sign in with magic link instead'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
