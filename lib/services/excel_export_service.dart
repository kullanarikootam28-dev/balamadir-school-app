import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// One tab of an exported workbook. Excel caps sheet names at 31 chars and
/// forbids a few characters; [ExcelExportService] sanitises the name.
class ExportSheet {
  const ExportSheet({required this.name, required this.headers, required this.rows});

  final String name;
  final List<String> headers;
  final List<List<Object?>> rows;
}

/// Module 18 of the client spec: "Export as Excel" alongside the existing
/// PDF exports (receipt_service.dart, report_card_pdf_service.dart). Builds
/// an .xlsx with the already-installed `excel` package and hands it to the
/// OS share sheet, same delivery pattern as every PDF export in this app.
///
/// Workbooks open directly in Google Sheets with every tab preserved
/// (Share → Drive → Open with Google Sheets), so admins get a "structured
/// gsheet" without the app needing a Google login.
class ExcelExportService {
  ExcelExportService._();

  static Future<void> exportRows({
    required String fileBaseName,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    return exportWorkbook(
      fileBaseName: fileBaseName,
      sheets: [ExportSheet(name: 'Report', headers: headers, rows: rows)],
    );
  }

  static Future<void> exportWorkbook({
    required String fileBaseName,
    required List<ExportSheet> sheets,
  }) async {
    final bytes = buildWorkbookBytes(sheets);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileBaseName.xlsx');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], subject: fileBaseName);
  }

  static List<int> buildWorkbookBytes(List<ExportSheet> sheets) {
    final workbook = xls.Excel.createExcel();
    final placeholderSheet = workbook.getDefaultSheet()!;
    final headerStyle = xls.CellStyle(bold: true);
    final usedNames = <String>{};
    String? firstName;

    for (final spec in sheets) {
      final name = _uniqueSheetName(spec.name, usedNames);
      firstName ??= name;
      final sheet = workbook[name];

      sheet.appendRow(spec.headers.map((h) => xls.TextCellValue(h)).toList());
      for (var col = 0; col < spec.headers.length; col++) {
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
            .cellStyle = headerStyle;
      }
      for (final row in spec.rows) {
        sheet.appendRow(row.map(_cellValue).toList());
      }
    }
    // createExcel() always starts with an empty "Sheet1"; drop it unless a
    // requested tab happens to share its name.
    if (!usedNames.contains(placeholderSheet)) workbook.delete(placeholderSheet);
    if (firstName != null) workbook.setDefaultSheet(firstName);

    final bytes = workbook.encode();
    if (bytes == null) throw Exception('Could not encode the spreadsheet.');
    return bytes;
  }

  /// Numbers stay numeric so the sheet can sum/sort them; everything else
  /// is text.
  static xls.CellValue? _cellValue(Object? value) {
    if (value == null) return xls.TextCellValue('');
    if (value is int) return xls.IntCellValue(value);
    if (value is double) return xls.DoubleCellValue(value);
    return xls.TextCellValue(value.toString());
  }

  static String _uniqueSheetName(String raw, Set<String> used) {
    var base = raw.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (base.isEmpty) base = 'Sheet';
    if (base.length > 31) base = base.substring(0, 31);
    var name = base;
    var n = 2;
    while (used.contains(name)) {
      final suffix = ' ($n)';
      name = '${base.substring(0, base.length.clamp(0, 31 - suffix.length))}$suffix';
      n++;
    }
    used.add(name);
    return name;
  }
}
