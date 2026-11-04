import 'package:file_picker/file_picker.dart';

import 'package:school_management_app/services/r2_gateway_service.dart';

/// Uploads a receipt/quotation/bill/before-after photo for an expense or
/// repair request to the `expense_documents/` prefix in Cloudflare R2 at
/// `expense_documents/<recordId>/<docType>.<ext>`. Mirrors
/// document_upload_service.dart's upload flow exactly, minus the "link into
/// a details table" step — the caller stores the returned path in the
/// relevant *_url column itself.
class ExpenseDocumentService {
  ExpenseDocumentService._();

  static Future<String?> pickAndUpload({
    required String recordId,
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
    final path = 'expense_documents/$recordId/$docType.$ext';

    await R2GatewayService.uploadBytes(
      path: path,
      bytes: bytes,
      contentType: R2GatewayService.contentTypeForExtension(ext),
    );

    return path;
  }

  static Future<String> signedUrl(String path) async {
    return R2GatewayService.fileUrl(path);
  }
}
