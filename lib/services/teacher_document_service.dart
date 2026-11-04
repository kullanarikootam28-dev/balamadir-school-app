import 'package:file_picker/file_picker.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/services/r2_gateway_service.dart';

/// Uploads a teacher document (Resume, Certificate, ID Proof) to the
/// `teacher_documents/` prefix in Cloudflare R2 at
/// `teacher_documents/<teacher_id>/<docType>.<ext>` and links its path into
/// the matching `teacher_details` column. Mirrors
/// document_upload_service.dart's student-side flow.
class TeacherDocumentService {
  TeacherDocumentService._();

  static const Map<String, String> docTypeColumns = {
    'resume': 'resume_url',
    'certificate': 'certificate_url',
    'id_proof': 'id_proof_url',
  };

  static const Map<String, String> docTypeLabels = {
    'resume': 'Resume',
    'certificate': 'Certificate',
    'id_proof': 'ID Proof',
  };

  static Future<String?> pickAndUpload({
    required String teacherId,
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
    final path = 'teacher_documents/$teacherId/$docType.$ext';

    await R2GatewayService.uploadBytes(
      path: path,
      bytes: bytes,
      contentType: R2GatewayService.contentTypeForExtension(ext),
    );

    final column = docTypeColumns[docType]!;
    await supabase.from('teacher_details').update({column: path}).eq('teacher_id', teacherId);

    return path;
  }

  static Future<String> signedUrl(String path) async {
    return R2GatewayService.fileUrl(path);
  }
}
