import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:school_management_app/config/supabase_config.dart';

/// Sign-in tokens last an hour and are checked against this device's own
/// clock. When a PC's clock or time zone is wrong (clock ahead by an hour or
/// more), every fresh token already looks expired: the app refreshes it in a
/// tight loop, hits the server's rate limit, and gets signed out — which
/// looks exactly like "correct password, no error, just doesn't log in".
/// The auth library is now patched so sign-in no longer depends on the
/// clock; this check remains to warn that dates/times will be off.
class ClockCheck {
  ClockCheck._();

  /// Beyond this, time-based features (sign-in, QR check-in windows,
  /// attendance dates) can't be trusted.
  static const Duration tolerance = Duration(minutes: 5);

  /// Server time minus this device's time, or null if the server couldn't
  /// be reached (the sign-in attempt will then report the network problem).
  static Future<Duration?> serverOffset() async {
    try {
      final response = await http
          .get(
            Uri.parse('${SupabaseConfig.projectUrl}/auth/v1/health'),
            headers: {'apikey': SupabaseConfig.anonKey},
          )
          .timeout(const Duration(seconds: 8));
      final date = response.headers['date'];
      if (date == null) return null;
      return HttpDate.parse(date).difference(DateTime.now().toUtc());
    } catch (_) {
      return null;
    }
  }

  /// Returns true to go ahead with signing in. Sign-in itself no longer
  /// depends on the clock (see third_party/gotrue/BALAMANDIR_PATCH.md), so a
  /// wrong clock only warns — but dates the app shows or saves (attendance,
  /// check-in times) still come from this device, so it's worth fixing.
  static Future<bool> ensureClockIsCorrect(BuildContext context) async {
    final offset = await serverOffset();
    if (offset == null || offset.abs() <= tolerance) return true;
    if (!context.mounted) return true;

    final correctTime = DateTime.now().add(offset);
    final minutes = offset.inMinutes.abs();
    final howFar = minutes >= 90
        ? '${(minutes / 60).toStringAsFixed(1)} hours'
        : '$minutes minutes';
    final direction = offset.isNegative ? 'ahead' : 'behind';
    final dateIsWrong = offset.abs() >= const Duration(hours: 12);
    final isWindows = Platform.isWindows;

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.schedule, color: Colors.orange, size: 40),
        title: const Text("This device's clock is wrong"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('It is $howFar $direction. The correct time is about '
                '${DateFormat('h:mm a, d MMM').format(correctTime)}.'),
            const SizedBox(height: 12),
            Text(
              dateIsWrong
                  ? 'Even the date is wrong, so attendance and anything else you save '
                      'could be recorded on the wrong day. Please fix the clock first.'
                  : 'You can still sign in, but times the app shows or saves may be off.',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: dateIsWrong ? Colors.red : null),
            ),
            const SizedBox(height: 12),
            Text(isWindows
                ? 'To fix it: Settings → Time & language → Date & time → turn ON '
                    '"Set time automatically" and "Set time zone automatically" '
                    '(or choose "(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi"), then '
                    'click "Sync now".'
                : 'To fix it: Settings → Date & time → turn ON "Automatic date & time" '
                    'and "Automatic time zone".'),
          ],
        ),
        actions: [
          if (isWindows)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'settings'),
              child: const Text('Open Date & Time settings'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'continue'),
            child: const Text('Sign in anyway'),
          ),
        ],
      ),
    );

    if (choice == 'settings') {
      await launchUrl(Uri.parse('ms-settings:dateandtime'));
      return false;
    }
    return choice == 'continue';
  }
}
