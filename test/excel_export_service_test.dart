import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';

import 'package:school_management_app/services/excel_export_service.dart';

void main() {
  test('builds one tab per sheet, drops the placeholder, keeps numbers numeric', () {
    final bytes = ExcelExportService.buildWorkbookBytes(const [
      ExportSheet(name: 'Teachers', headers: ['Name', 'Days'], rows: [
        ['Asha', 20],
        ['Ravi', 18],
      ]),
      ExportSheet(name: 'Attendance Summary', headers: ['Name', 'Percent'], rows: [
        ['Asha', 95.5],
      ]),
    ]);

    final book = xls.Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['Teachers', 'Attendance Summary']));
    expect(book.tables.keys, isNot(contains('Sheet1')));

    final teachers = book.tables['Teachers']!;
    expect(teachers.maxRows, 3);
    final header = teachers.cell(xls.CellIndex.indexByString('A1'));
    expect(header.value.toString(), 'Name');
    expect(header.cellStyle?.isBold, isTrue);
    expect(teachers.cell(xls.CellIndex.indexByString('B2')).value, isA<xls.IntCellValue>());

    final summary = book.tables['Attendance Summary']!;
    expect(summary.cell(xls.CellIndex.indexByString('B2')).value, isA<xls.DoubleCellValue>());
  });

  test('sanitises and de-duplicates sheet names', () {
    final bytes = ExcelExportService.buildWorkbookBytes(const [
      ExportSheet(name: 'Daily/Log: 2026', headers: ['A'], rows: []),
      ExportSheet(name: 'Daily/Log: 2026', headers: ['A'], rows: []),
      ExportSheet(
          name: 'An extremely long sheet name that exceeds the limit', headers: ['A'], rows: []),
    ]);
    final names = xls.Excel.decodeBytes(bytes).tables.keys.toList();
    expect(names, hasLength(3));
    expect(names.every((n) => n.length <= 31), isTrue);
    expect(names.any((n) => n.contains('/') || n.contains(':')), isFalse);
  });
}
