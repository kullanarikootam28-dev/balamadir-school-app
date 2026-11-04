import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:school_management_app/services/broadcast_media_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Downloads a notice attachment from Cloudflare R2 (via the Worker URL
/// stored on the notice) and lets the person choose where to save it —
/// the phone's "Save to" screen on Android, a Save dialog on Windows.
class AttachmentDownloadService {
  AttachmentDownloadService._();

  static Future<void> download(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final fileName = BroadcastMediaService.fileNameFor(url);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Downloading $fileName…'),
        duration: const Duration(minutes: 2),
      ));

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        throw FriendlyException(response.statusCode == 404
            ? 'This file is no longer available.'
            : 'Download failed (error ${response.statusCode}). Please try again.');
      }
      final bytes = response.bodyBytes;
      messenger.clearSnackBars();

      String? savedPath;
      if (Platform.isAndroid || Platform.isIOS) {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save $fileName',
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        // Desktop: the dialog only picks the location; we write the file.
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save $fileName',
          fileName: fileName,
        );
        if (savedPath != null) await File(savedPath).writeAsBytes(bytes, flush: true);
      }

      if (savedPath == null) return; // cancelled
      final path = savedPath;
      messenger.showSnackBar(SnackBar(
        content: Text('Saved $fileName'),
        action: Platform.isWindows
            ? SnackBarAction(
                label: 'Open',
                onPressed: () => launchUrl(Uri.file(path)),
              )
            : null,
      ));
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: Colors.red,
        ));
    }
  }

  /// Opens the file in the phone/PC's own viewer (browser, PDF reader,
  /// video player) straight from R2, without saving a copy.
  static Future<void> open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
