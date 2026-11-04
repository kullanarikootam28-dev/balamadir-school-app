import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

const _kSchoolName = 'Balamandir Matriculation School';
const _kSchoolAddress = 'B.Pudur, Mittapalli, Uthangarai Tk, Krishnagiri Dt, Tamil Nadu, India';

/// Generates a one-page fee receipt PDF and hands it to the OS share sheet.
///
/// Branded in the school's own name (not the app's) per the client's sample
/// — logo, institution name/address, "Electronic Receipt" framing, and the
/// system-generated/no-signature note, matching how the school's existing
/// SRM-style receipts read.
///
/// This is a deliberate stand-in for automated delivery: today the admin taps
/// "Share Receipt" and picks WhatsApp/email themselves from the share sheet.
/// Once a WhatsApp Business API number is acquired, the same PDF bytes this
/// builds can be POSTed by an API call instead — the document itself doesn't
/// change, only the trigger.
class ReceiptService {
  ReceiptService._();

  static Future<void> shareReceipt({
    required String studentName,
    required String invoiceId,
    required int amountPaise,
    required String status,
    DateTime? paidAt,
    DateTime? dueDate,
    String? description,
    String? paymentMode,
    String? transactionRef,
  }) async {
    final doc = pw.Document();
    final amount = (amountPaise / 100).toStringAsFixed(2);
    final dateFormat = DateFormat('d MMM yyyy');
    final logoBytes = await rootBundle.load('assets/images/logo.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(width: 48, height: 48, child: pw.Image(logo)),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(_kSchoolName,
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.Text(_kSchoolAddress, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Text('Electronic Receipt',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
            ),
            pw.SizedBox(height: 16),
            _row('Receipt No.', invoiceId),
            _row('To', studentName),
            pw.SizedBox(height: 8),
            pw.Text(
              'Amount Received: ₹$amount${description != null ? ' towards $description' : ''}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 8),
            _row('Status', status.toUpperCase()),
            if (paymentMode != null) _row('Payment Mode', paymentMode),
            if (transactionRef != null && transactionRef.isNotEmpty)
              _row('Transaction Ref', transactionRef),
            if (dueDate != null) _row('Due Date', dateFormat.format(dueDate)),
            if (paidAt != null) _row('Paid On', dateFormat.format(paidAt)),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text(
                'This is a system generated receipt and does not require a signature.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Generated on ${dateFormat.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt_$invoiceId.pdf');
    await file.writeAsBytes(await doc.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Fee Receipt - $invoiceId',
      text: 'Fee receipt for $studentName ($invoiceId)',
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
