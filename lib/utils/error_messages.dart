import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// An error whose message is already written for the person using the app
/// (e.g. "That file is 72 MB — attachments can be up to 50 MB").
class FriendlyException implements Exception {
  const FriendlyException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Postgres wording that only means something to a developer — anything
/// else raised by our own database functions (e.g. "You can't delete your
/// own account") is already written for the person using the app.
bool _isTechnical(String message) {
  final m = message.toLowerCase();
  return m.contains('violates') ||
      m.contains('permission denied') ||
      m.contains('row-level security') ||
      m.contains('relation ') ||
      m.contains('column ') ||
      m.contains('function ') ||
      m.contains('syntax') ||
      m.contains('null value') ||
      m.contains('invalid input');
}

String _friendlyAuthMessage(AuthException error) {
  final m = error.message;
  final lower = m.toLowerCase();
  if (lower.contains('invalid login credentials')) {
    return 'Wrong email or password. Check both (including .com at the end of the email) '
        'and try again. The school office can set a new password for you.';
  }
  if (lower.contains('email address') && lower.contains('invalid')) {
    return 'This email address can\'t receive mail — check the spelling '
        '(for example .com, not .con).';
  }
  if (error.statusCode == '429' || lower.contains('rate limit') || lower.contains('too many')) {
    return 'Too many attempts. Wait a few minutes and try again.';
  }
  if (lower.contains('signups not allowed') || lower.contains('signup is disabled')) {
    return 'New accounts can only be created by the school office.';
  }
  if (lower.contains('email not confirmed')) {
    return 'This account isn\'t activated yet. Ask the school office to check it.';
  }
  if (error is AuthRetryableFetchException) {
    return "Can't reach the server. Check your internet connection and try again.";
  }
  return m;
}

/// Turns a raw exception into a short, human-readable message safe to show
/// directly in a SnackBar/dialog — never a raw `PostgrestException(...)` dump
/// or an internal error like "Null check operator used on a null value".
String friendlyErrorMessage(Object error) {
  if (error is FriendlyException) return error.message;

  if (error is TimeoutException) {
    return "The server didn't answer. Check the internet connection — and if other "
        'sites work, allow this app through the firewall or antivirus.';
  }

  if (error is SocketException) {
    return "You're offline. Check your internet connection and try again.";
  }

  if (error is HandshakeException) {
    return "Couldn't make a secure connection. Check that this device's date and time "
        'are correct, then try again.';
  }

  if (error is AuthException) {
    return _friendlyAuthMessage(error);
  }

  if (error is StorageException) {
    return 'File upload failed. Please try again.';
  }

  if (error is PostgrestException) {
    // Messages our own database functions raise on purpose.
    if (const {'42501', '22023', '23505', 'P0002', 'P0001'}.contains(error.code) &&
        !_isTechnical(error.message)) {
      return error.message;
    }
    switch (error.code) {
      case '23505':
        return 'This already exists.';
      case '42501':
        return "You don't have permission to do this.";
      case '23503':
        return "This is linked to other records and can't be changed.";
      default:
        return 'Something went wrong on the server. Please try again.';
    }
  }

  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection failed') ||
      text.contains('Connection closed') ||
      text.contains('Network is unreachable')) {
    return "You're offline. Check your internet connection and try again.";
  }
  if (text.contains('CERTIFICATE_VERIFY_FAILED') || text.contains('HandshakeException')) {
    return "Couldn't make a secure connection. Check that this device's date and time "
        'are correct, then try again.';
  }

  return 'Something went wrong. Please try again.';
}
