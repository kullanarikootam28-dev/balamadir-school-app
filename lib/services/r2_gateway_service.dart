import 'package:http/http.dart' as http;

import 'package:school_management_app/main.dart';

/// Shared primitives every file-upload service (avatar, broadcast media,
/// student/teacher/expense documents) calls, talking to the Cloudflare
/// Worker gateway (cloudflare-worker/index.js) instead of Supabase Storage.
/// The Worker replicates the same admin/owner/public read-write matrix the
/// old Storage RLS policies encoded — see the Worker's own comments.
class R2GatewayService {
  R2GatewayService._();

  static const String _workerUrl = 'https://balamandirschool.ajainawin.workers.dev';

  static String? get _accessToken => supabase.auth.currentSession?.accessToken;

  /// Uploads raw bytes to `path` (e.g. `student_documents/<id>/photo.jpg`).
  /// Throws if the caller isn't authorized to write there — the Worker
  /// enforces this, not the client.
  static Future<void> uploadBytes({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    final uri = Uri.parse('$_workerUrl/upload').replace(queryParameters: {'path': path});
    final response = await http.post(
      uri,
      headers: {
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        'Content-Type': contentType,
      },
      body: bytes,
    );
    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }
  }

  static const List<String> _publicPrefixes = ['avatars/', 'broadcast_media/'];

  /// A directly-usable URL for `path`. For the two public prefixes
  /// (avatars/, broadcast_media/) this is a clean permanent URL — no token,
  /// since the Worker never checks one for these — matching how
  /// broadcast_media_service.dart's isVideo() sniffs the URL's file
  /// extension and would break if a `?token=` suffix were appended. For
  /// private prefixes, the token is embedded as a query parameter so the
  /// URL also works when opened externally (launchUrl), mirroring how
  /// Supabase's own createSignedUrl already embeds its token.
  static String fileUrl(String path) {
    final base = '$_workerUrl/file/$path';
    final isPublic = _publicPrefixes.any((p) => path.startsWith(p));
    if (isPublic) return base;
    final token = _accessToken;
    return token == null ? base : '$base?token=$token';
  }

  /// R2 needs an explicit content-type on write (unlike Supabase Storage's
  /// uploadBinary, which infers it). Covers photos, videos and the document
  /// types teachers attach to notices.
  static String contentTypeForExtension(String ext) {
    const types = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'pdf': 'application/pdf',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'mkv': 'video/x-matroska',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'zip': 'application/zip',
    };
    return types[ext.toLowerCase()] ?? 'application/octet-stream';
  }
}
