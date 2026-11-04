import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Per-teacher PDF export for the Teacher Records module — same
/// pw.Document + temp-file + share_plus pattern as report_card_pdf_service.dart.
class TeacherRecordPdfService {
  TeacherRecordPdfService._();

  static Future<void> downloadRecord({
    required String fullName,
    required String email,
    String? phone,
    String? qualification,
    String? specialization,
    String? experienceYears,
    DateTime? joiningDate,
    String? status,
    required List<Map<String, dynamic>> assignments,
    double? averagePercent,
  }) async {
    final doc = pw.Document();
    final dateFormat = DateFormat('d MMM yyyy');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(children: [
                pw.Text('Balamandir School App',
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text('Teacher Record', style: const pw.TextStyle(fontSize: 12)),
              ]),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            _row('Name', fullName),
            _row('Email', email),
            if (phone != null && phone.isNotEmpty) _row('Phone', phone),
            if (qualification != null && qualification.isNotEmpty) _row('Qualification', qualification),
            if (specialization != null && specialization.isNotEmpty)
              _row('Specialization', specialization),
            if (experienceYears != null && experienceYears.isNotEmpty)
              _row('Experience', '$experienceYears years'),
            if (joiningDate != null) _row('Date of joining', dateFormat.format(joiningDate)),
            if (status != null) _row('Status', status.toUpperCase()),
            if (averagePercent != null)
              _row('Average performance', '${averagePercent.toStringAsFixed(1)}%'),
            pw.Divider(),
            pw.SizedBox(height: 12),
            pw.Text('Assigned subjects & classes',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (assignments.isEmpty)
              pw.Text('No assignments on file')
            else
              ...assignments.map((a) {
                final cls = a['classes'] as Map?;
                final subject = (a['subjects'] as Map?)?['name'] as String? ?? '—';
                final className = cls != null ? 'Grade ${cls['grade']} - ${cls['section']}' : '—';
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text('$className — $subject'),
                );
              }),
            pw.SizedBox(height: 12),
            pw.Text('Generated on ${dateFormat.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/teacher_record_${fullName.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await doc.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Teacher Record - $fullName',
      text: 'Teacher record for $fullName',
    );
  }

  static pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );
}
