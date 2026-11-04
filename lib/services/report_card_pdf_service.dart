import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:school_management_app/models/grade.dart';

/// Module 19 of the client spec: Report Card with school name, student
/// details, subject marks, percentage/grade/rank, teacher remarks, and a
/// principal-signature line — downloadable as PDF. Follows the same
/// pw.Document + temp-file + share_plus pattern as receipt_service.dart.
class ReportCardPdfService {
  ReportCardPdfService._();

  static Future<void> downloadReportCard({
    required String studentName,
    required String className,
    required List<Grade> grades,
    required double overallPercent,
    required String overallGrade,
    int? rank,
    int? totalInClass,
    String? remarks,
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
              child: pw.Column(
                children: [
                  pw.Text('Balamandir School App',
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Academic Report Card', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            _row('Student', studentName),
            _row('Class', className),
            _row('Generated on', dateFormat.format(DateTime.now())),
            pw.Divider(),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1.5),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Subject', bold: true),
                    _cell('Score', bold: true),
                    _cell('Max', bold: true),
                    _cell('%', bold: true),
                  ],
                ),
                for (final g in grades)
                  pw.TableRow(children: [
                    _cell(g.subjectName),
                    _cell(g.score.toStringAsFixed(0)),
                    _cell(g.maxScore.toStringAsFixed(0)),
                    _cell(g.percentage.toStringAsFixed(1)),
                  ]),
              ],
            ),
            pw.SizedBox(height: 20),
            _row('Overall percentage', '${overallPercent.toStringAsFixed(1)}%'),
            _row('Overall grade', overallGrade),
            if (rank != null && totalInClass != null)
              _row('Class rank', '$rank of $totalInClass'),
            if (remarks != null && remarks.trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text('Teacher remarks:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(remarks),
            ],
            pw.SizedBox(height: 48),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 140, child: pw.Divider(thickness: 1)),
                    pw.Text('Class Teacher'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 140, child: pw.Divider(thickness: 1)),
                    pw.Text('Principal'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/report_card_${studentName.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(await doc.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Report Card - $studentName',
      text: 'Academic report card for $studentName',
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

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
}
