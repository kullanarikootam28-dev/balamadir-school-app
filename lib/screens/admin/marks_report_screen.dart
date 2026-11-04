import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/grade.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/subject_colors.dart';
import 'package:school_management_app/utils/error_messages.dart';

class MarksReportScreen extends StatefulWidget {
  const MarksReportScreen({super.key});

  @override
  State<MarksReportScreen> createState() => _MarksReportScreenState();
}

class _MarksReportScreenState extends State<MarksReportScreen> {
  bool _loadingClasses = true;
  bool _loadingGrades = false;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  String? _selectedSubject;
  List<Grade> _grades = [];
  final Map<String, String> _studentNames = {};

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final data =
          await supabase.from(SupabaseConfig.classesTable).select().order('grade');
      setState(() {
        _classes = (data as List)
            .map((e) => ClassModel.fromJson(e as Map<String, dynamic>))
            .toList();
        if (_classes.isNotEmpty) _selectedClass = _classes.first;
      });
      if (_selectedClass != null) await _loadGrades();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadGrades() async {
    if (_selectedClass == null) return;
    setState(() => _loadingGrades = true);
    try {
      final data = await supabase
          .from(SupabaseConfig.gradesTable)
          .select('*, profiles(full_name)')
          .eq('class_id', _selectedClass!.id);
      final rows = List<Map<String, dynamic>>.from(data);
      _studentNames.clear();
      for (final r in rows) {
        final id = r['student_id'] as String;
        _studentNames[id] = (r['profiles'] as Map?)?['full_name'] as String? ?? 'Unknown';
      }
      setState(() {
        _grades = rows.map((e) => Grade.fromJson(e)).toList();
        _selectedSubject = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingGrades = false);
    }
  }

  List<String> get _subjects => _grades.map((g) => g.subjectName).toSet().toList()..sort();

  Map<String, double> get _averageBySubject {
    final bySubject = <String, List<Grade>>{};
    for (final g in _grades) {
      bySubject.putIfAbsent(g.subjectName, () => []).add(g);
    }
    return bySubject.map((subject, grades) => MapEntry(
        subject, grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length));
  }

  Map<String, double> get _scoresForSelectedSubject {
    final matching = _grades.where((g) => g.subjectName == _selectedSubject).toList();
    final byStudent = <String, List<Grade>>{};
    for (final g in matching) {
      byStudent.putIfAbsent(g.studentId, () => []).add(g);
    }
    return byStudent.map((studentId, grades) => MapEntry(
        _studentNames[studentId] ?? 'Unknown',
        grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length));
  }

  Future<void> _exportExcel() async {
    final showingSubject = _selectedSubject != null;
    final data = showingSubject ? _scoresForSelectedSubject : _averageBySubject;
    try {
      await ExcelExportService.exportRows(
        fileBaseName: 'marks_report_${_selectedClass?.displayName.replaceAll(' ', '_') ?? 'all'}',
        headers: [showingSubject ? 'Student' : 'Subject', 'Average %'],
        rows: data.entries.map((e) => [e.key, e.value.toStringAsFixed(1)]).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showingSubject = _selectedSubject != null;
    final data = showingSubject ? _scoresForSelectedSubject : _averageBySubject;
    final labels = data.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marks Reports'),
        actions: [
          if (_grades.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.table_view_outlined),
              tooltip: 'Export Excel',
              onPressed: _exportExcel,
            ),
        ],
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      DropdownButtonFormField<ClassModel>(
                        initialValue: _selectedClass,
                        decoration: const InputDecoration(labelText: 'Class'),
                        items: _classes
                            .map((c) => DropdownMenuItem(value: c, child: Text(c.displayName)))
                            .toList(),
                        onChanged: (c) {
                          setState(() => _selectedClass = c);
                          _loadGrades();
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedSubject,
                        decoration:
                            const InputDecoration(labelText: 'Subject (optional — per-student view)'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('All subjects (class average)')),
                          ..._subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                        ],
                        onChanged: (v) => setState(() => _selectedSubject = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadingGrades
                      ? const Center(child: CircularProgressIndicator())
                      : _grades.isEmpty
                          ? const Center(child: Text('No grades recorded for this class'))
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                SizedBox(
                                  height: 260,
                                  child: BarChart(
                                    BarChartData(
                                      maxY: 100,
                                      barGroups: [
                                        for (var i = 0; i < labels.length; i++)
                                          BarChartGroupData(x: i, barRods: [
                                            BarChartRodData(
                                              toY: data[labels[i]]!,
                                              color: showingSubject
                                                  ? Theme.of(context).colorScheme.primary
                                                  : subjectColor(labels[i]),
                                              width: 22,
                                            ),
                                          ]),
                                      ],
                                      titlesData: FlTitlesData(
                                        leftTitles: const AxisTitles(
                                            sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                                        topTitles:
                                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        rightTitles:
                                            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 42,
                                            getTitlesWidget: (value, meta) {
                                              final idx = value.toInt();
                                              if (idx < 0 || idx >= labels.length) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 6),
                                                child: Transform.rotate(
                                                  angle: -0.5,
                                                  child: Text(labels[idx],
                                                      style: const TextStyle(fontSize: 9)),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                                      borderData: FlBorderData(show: false),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  showingSubject ? '$_selectedSubject — per student' : 'Subject averages',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                ...labels.map((label) => Card(
                                      child: ListTile(
                                        title: Text(label),
                                        trailing: Text('${data[label]!.toStringAsFixed(1)}%',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    )),
                              ],
                            ),
                ),
              ],
            ),
    );
  }
}
