import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Tabular PDF export for the Expense Reports tab — same
/// generate-then-share pattern as receipt_service.dart, generalized to an
/// arbitrary header/rows table instead of one fixed receipt layout.
class ExpensePdfService {
  ExpensePdfService._();

  static Future<void> exportTable({
    required String title,
    required String fileBaseName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileBaseName.pdf');
    await file.writeAsBytes(await doc.save());

    await Share.shareXFiles([XFile(file.path)], subject: title);
  }
}
