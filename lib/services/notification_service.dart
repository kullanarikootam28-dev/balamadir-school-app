import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/notification_log.dart';

/// Notification triggers without any Meta/WhatsApp Business API
/// authentication: this composes the message and opens a `wa.me` deep link
/// (same mechanism already used in profile_detail_screen.dart) so a staff
/// member reviews and taps Send themselves. Every trigger is logged to
/// `notification_log` regardless of whether the external app is actually
/// available, so the audit trail is real even though sending stays manual.
class NotificationService {
  NotificationService._();

  static String compose(
    NotificationTrigger trigger, {
    required String studentName,
    String? amountDisplay,
    String? subjectName,
    String? detail,
  }) {
    switch (trigger) {
      case NotificationTrigger.feeReminder:
        return 'Dear Parent, this is a reminder that a fee payment of '
            '${amountDisplay ?? ''} for $studentName is pending. Please pay '
            'at the earliest. — Balamandir School';
      case NotificationTrigger.feePayment:
        return 'Dear Parent, we have received a fee payment of '
            '${amountDisplay ?? ''} for $studentName. Thank you. — '
            'Balamandir School';
      case NotificationTrigger.attendance:
        return 'Dear Parent, $studentName was marked ${detail ?? ''} today. '
            '— Balamandir School';
      case NotificationTrigger.marksPublished:
        return 'Dear Parent, marks for $studentName in '
            '${subjectName ?? 'a subject'} have been published. Please '
            'check the app for details. — Balamandir School';
      case NotificationTrigger.event:
        return 'Dear Parent, ${detail ?? 'there is a school update'} — '
            'Balamandir School';
    }
  }

  static Future<void> sendViaWhatsApp({
    required BuildContext context,
    required String phone,
    required String message,
    required NotificationTrigger trigger,
    String? studentId,
  }) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }

    try {
      await supabase.from('notification_log').insert({
        'student_id': studentId,
        'trigger_type': NotificationLogEntry.triggerToJson(trigger),
        'channel': 'whatsapp',
        'message': message,
        'sent_by': supabase.auth.currentUser?.id,
      });
    } catch (_) {
      // Logging is best-effort; the WhatsApp launch above already happened.
    }
  }
}
