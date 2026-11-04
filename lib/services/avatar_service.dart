import 'package:file_picker/file_picker.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/r2_gateway_service.dart';

/// Uploads a profile photo ("ID card" image) to the `avatars/` prefix in
/// Cloudflare R2 and links it to a profile row. Admin-only — enforced by
/// the Worker gateway (cloudflare-worker/index.js), which mirrors the old
/// bucket's RLS policies (see migration 007_avatar_storage.sql). Public
/// prefix, so the returned URL works directly in Image.network.
class AvatarService {
  AvatarService._();

  static Future<String?> pickAndUpload(String profileId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) throw Exception('Could not read the selected image.');

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final path = 'avatars/$profileId.$ext';

    await R2GatewayService.uploadBytes(
      path: path,
      bytes: bytes,
      contentType: R2GatewayService.contentTypeForExtension(ext),
    );

    // Cache-bust so <Image.network>/CachedNetworkImage picks up the new
    // photo immediately instead of showing a stale cached copy at the same
    // URL.
    final baseUrl = R2GatewayService.fileUrl(path);
    final separator = baseUrl.contains('?') ? '&' : '?';
    final publicUrl = '$baseUrl${separator}t=${DateTime.now().millisecondsSinceEpoch}';

    await supabase
        .from(SupabaseConfig.profilesTable)
        .update({'avatar_url': publicUrl}).eq('id', profileId);

    return publicUrl;
  }
}
