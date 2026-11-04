import 'package:file_picker/file_picker.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/r2_gateway_service.dart';

/// Uploads a student document (Photo, Birth Certificate, Aadhaar, Transfer
/// Certificate) to the `student_documents/` prefix in Cloudflare R2 at
/// `student_documents/<student_id>/<docType>.<ext>` and links its path into
/// the matching `student_details` column. Private prefix — viewing requires
/// a token, brokered by the Worker gateway (cloudflare-worker/index.js)
/// rather than Supabase's createSignedUrl.
class DocumentUploadService {
  DocumentUploadService._();

  static const Map<String, String> docTypeColumns = {
    'photo': 'photo_url',
    'birth_certificate': 'birth_certificate_url',
    'aadhaar': 'aadhaar_doc_url',
    'tc': 'tc_url',
  };

  static const Map<String, String> docTypeLabels = {
    'photo': 'Photo',
    'birth_certificate': 'Birth Certificate',
    'aadhaar': 'Aadhaar',
    'tc': 'Transfer Certificate',
  };

  static Future<String?> pickAndUpload({
    required String studentId,
    required String docType,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) throw Exception('Could not read the selected file.');

    final ext = (file.extension ?? 'pdf').toLowerCase();
    final path = 'student_documents/$studentId/$docType.$ext';

    await R2GatewayService.uploadBytes(
      path: path,
      bytes: bytes,
      contentType: R2GatewayService.contentTypeForExtension(ext),
    );

    final column = docTypeColumns[docType]!;
    await supabase.from('student_details').update({column: path}).eq('student_id', studentId);

    return path;
  }

  static Future<String> signedUrl(String path) async {
    return R2GatewayService.fileUrl(path);
  }
}
