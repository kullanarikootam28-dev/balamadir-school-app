import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:school_management_app/models/import_result.dart';
import 'package:school_management_app/services/spreadsheet_import_service.dart';

class SpreadsheetImportScreen extends StatefulWidget {
  const SpreadsheetImportScreen({super.key});

  @override
  State<SpreadsheetImportScreen> createState() => _SpreadsheetImportScreenState();
}

class _SpreadsheetImportScreenState extends State<SpreadsheetImportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spreadsheet Import'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'Classes'), Tab(text: 'Timetable'), Tab(text: 'Students')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ImportTab(
            key: PageStorageKey('classes'),
            sampleFileName: 'classes_sample',
            fields: [
              _ImportField('grade', 'Grade'),
              _ImportField('section', 'Section'),
              _ImportField('academic_year', 'Academic Year', required: false),
              _ImportField('teacher_email', 'Teacher Email', required: false),
            ],
            sampleRows: [
              ['9', 'B', '2026', 'teacher.test@schoolapp.dev'],
              ['10', 'A', '2026', ''],
            ],
            formatGuide: 'One row per class. Required: Grade, Section. Optional: '
                'Academic Year (defaults to the current year), Teacher Email '
                '(must match an existing teacher account).',
            onImport: SpreadsheetImportService.importClasses,
          ),
          _ImportTab(
            key: PageStorageKey('timetable'),
            sampleFileName: 'timetable_sample',
            fields: [
              _ImportField('grade', 'Grade'),
              _ImportField('section', 'Section'),
              _ImportField('academic_year', 'Academic Year', required: false),
              _ImportField('day_of_week', 'Day of Week'),
              _ImportField('period_number', 'Period Number'),
              _ImportField('subject_name', 'Subject', required: false),
              _ImportField('teacher_email', 'Teacher Email', required: false),
              _ImportField('start_time', 'Start Time'),
              _ImportField('end_time', 'End Time'),
            ],
            sampleRows: [
              [
                '10',
                'A',
                '2026',
                'Monday',
                '1',
                'Mathematics',
                'teacher.test@schoolapp.dev',
                '09:00',
                '09:45'
              ],
              ['10', 'A', '2026', 'Monday', '2', 'Science', '', '09:45', '10:30'],
            ],
            formatGuide: 'One row per period. Grade/Section must match an existing '
                'class. Day of Week can be 1-7 or a day name (e.g. Monday). Times '
                'use HH:MM (24-hour).',
            onImport: SpreadsheetImportService.importTimetable,
          ),
          _ImportTab(
            key: PageStorageKey('students'),
            sampleFileName: 'students_sample',
            fields: [
              _ImportField('full_name', 'Full Name'),
              _ImportField('email', 'Email'),
              _ImportField('roll_number', 'Roll Number', required: false),
              _ImportField('grade', 'Grade'),
              _ImportField('section', 'Section'),
              _ImportField('academic_year', 'Academic Year', required: false),
              _ImportField('phone', 'Phone', required: false),
            ],
            sampleRows: [
              ['Jane Doe', 'jane.doe@example.com', '1', '10', 'A', '2026', '9999999999'],
              ['John Smith', 'john.smith@example.com', '2', '10', 'A', '2026', ''],
            ],
            formatGuide: 'One row per student. Grade/Section must match an existing '
                'class. If the email doesn\'t match an existing account, a new '
                'student login is created automatically with a generated password '
                'shown after import.',
            onImport: SpreadsheetImportService.importStudents,
            showGeneratedAccounts: true,
          ),
        ],
      ),
    );
  }
}

class _ImportField {
  const _ImportField(this.key, this.label, {this.required = true});
  final String key;
  final String label;
  final bool required;
}

class _ImportTab extends StatefulWidget {
  const _ImportTab({
    super.key,
    required this.fields,
    required this.formatGuide,
    required this.onImport,
    required this.sampleFileName,
    required this.sampleRows,
    this.showGeneratedAccounts = false,
  });

  final List<_ImportField> fields;
  final String formatGuide;
  final Future<ImportResult> Function(ParsedSheet, ColumnMapping) onImport;
  final bool showGeneratedAccounts;
  final String sampleFileName;
  final List<List<String>> sampleRows;

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab>
    with AutomaticKeepAliveClientMixin {
  ParsedSheet? _sheet;
  String? _fileName;
  final ColumnMapping _mapping = {};
  bool _busy = false;
  ImportResult? _result;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final sheet = await SpreadsheetImportService.parseFile(file);
      setState(() {
        _sheet = sheet;
        _fileName = file.name;
        _mapping
          ..clear()
          ..addAll(_bestEffortMapping(sheet.headers));
      });
    } catch (e) {
      setState(() => _error = 'Failed to read file: $e');
    }
  }

  Future<void> _downloadSample() async {
    try {
      await SpreadsheetImportService.shareSampleSheet(
        fileBaseName: widget.sampleFileName,
        headers: widget.fields.map((f) => f.label).toList(),
        sampleRows: widget.sampleRows,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not generate sample sheet: $e');
      }
    }
  }

  Map<String, int?> _bestEffortMapping(List<String> headers) {
    final map = <String, int?>{};
    for (final field in widget.fields) {
      final targetWords = field.key.split('_');
      int? found;
      for (var i = 0; i < headers.length; i++) {
        final h = headers[i].toLowerCase().replaceAll(RegExp(r'[^a-z]+'), ' ');
        if (targetWords.every((w) => h.contains(w))) {
          found = i;
          break;
        }
      }
      map[field.key] = found;
    }
    return map;
  }

  Future<void> _runImport() async {
    if (_sheet == null) return;
    for (final field in widget.fields) {
      if (field.required && _mapping[field.key] == null) {
        setState(() => _error = '"${field.label}" must be mapped to a column before importing.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.onImport(_sheet!, _mapping);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sheet = _sheet;
    final previewCount = sheet == null ? 0 : (sheet.rows.length < 5 ? sheet.rows.length : 5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text('Format guide'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                Align(alignment: Alignment.centerLeft, child: Text(widget.formatGuide)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName ?? 'Pick .xlsx or .csv file'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _downloadSample,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Download sample sheet'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (sheet != null) ...[
            const SizedBox(height: 20),
            Text('Map columns',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...widget.fields.map((field) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DropdownButtonFormField<int?>(
                    initialValue: _mapping[field.key],
                    decoration: InputDecoration(
                      labelText: field.required ? '${field.label} *' : '${field.label} (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('— not mapped —')),
                      for (var i = 0; i < sheet.headers.length; i++)
                        DropdownMenuItem<int?>(value: i, child: Text(sheet.headers[i])),
                    ],
                    onChanged: (v) => setState(() => _mapping[field.key] = v),
                  ),
                )),
            const SizedBox(height: 12),
            Text('Preview (first $previewCount of ${sheet.rows.length} rows)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: widget.fields.map((f) => DataColumn(label: Text(f.label))).toList(),
                rows: sheet.rows.take(5).map((row) {
                  return DataRow(
                    cells: widget.fields.map((f) {
                      final idx = _mapping[f.key];
                      final value = idx != null && idx < row.length ? row[idx] : '';
                      return DataCell(Text(value));
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _runImport,
              child: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Import ${sheet.rows.length} rows'),
            ),
          ],
          if (_result case final result?) ...[
            const SizedBox(height: 24),
            Card(
              color: Colors.green.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${result.successCount} row(s) imported successfully',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (result.errors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('${result.errors.length} row(s) failed:',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      ...result.errors.map((e) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Row ${e.row}: ${e.message}',
                                style: const TextStyle(fontSize: 12)),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.showGeneratedAccounts && result.newAccounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "New accounts created — save these now, they won't be shown again:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...result.newAccounts.map((a) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SelectableText('${a.name} — ${a.email} — ${a.password}'),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
