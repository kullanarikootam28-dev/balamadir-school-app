import 'package:file_picker/file_picker.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/r2_gateway_service.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Uploads a notice/broadcast attachment — any file: photo, video, PDF,
/// Word/Excel/PowerPoint... — to the `broadcast_media/` prefix in
/// Cloudflare R2 and returns its URL. Students then view and download it
/// from R2 through the Worker too (never Supabase Storage). Admin or
/// teacher, per the Worker gateway's write check.
class BroadcastMediaService {
  BroadcastMediaService._();

  /// Keeps uploads reasonable for students downloading on mobile data (the
  /// Worker itself accepts up to 100 MB on Cloudflare's free plan).
  static const int maxBytes = 50 * 1024 * 1024;

  static Future<String?> pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > maxBytes) {
      throw FriendlyException('That file is ${(file.size / 1048576).toStringAsFixed(1)} MB — '
          'attachments can be up to 50 MB.');
    }
    final bytes = file.bytes;
    if (bytes == null) throw const FriendlyException('Could not read the selected file.');

    // The original name is kept (made URL-safe) as the last path segment, so
    // a student's download is saved as "Unit_Test_Syllabus.pdf", not a code.
    final ext = (file.extension ?? 'bin').toLowerCase();
    final dot = file.name.lastIndexOf('.');
    final baseName = (dot > 0 ? file.name.substring(0, dot) : file.name)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final safeBase = baseName.isEmpty ? 'attachment' : baseName;
    final path = 'broadcast_media/${DateTime.now().millisecondsSinceEpoch}_'
        '${supabase.auth.currentUser!.id}/'
        '${safeBase.length > 80 ? safeBase.substring(0, 80) : safeBase}.$ext';

    await R2GatewayService.uploadBytes(
      path: path,
      bytes: bytes,
      contentType: R2GatewayService.contentTypeForExtension(ext),
    );

    return R2GatewayService.fileUrl(path);
  }

  static String _ext(String url) {
    final name = Uri.tryParse(url)?.pathSegments.lastOrNull ?? url;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static bool isVideo(String url) => const {'mp4', 'mov', 'webm', 'mkv'}.contains(_ext(url));

  static bool isImage(String url) =>
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(_ext(url));

  /// The name a download is saved under. Older uploads were stored as
  /// "<timestamp>_<user id>.jpg" — those become "attachment.jpg".
  static String fileNameFor(String url) {
    final name = Uri.tryParse(url)?.pathSegments.lastOrNull ?? 'attachment';
    if (RegExp(r'^\d{10,}_[0-9a-f-]{36}\.').hasMatch(name)) {
      return 'attachment.${_ext(url)}';
    }
    return Uri.decodeComponent(name);
  }
}
