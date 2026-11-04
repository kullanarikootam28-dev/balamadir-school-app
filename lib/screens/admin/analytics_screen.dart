import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/attendance.dart';
import 'package:school_management_app/models/class_model.dart';
import 'package:school_management_app/models/grade.dart';
import 'package:school_management_app/services/analytics_service.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/fetch_all.dart';

/// Module 21 of the client spec, built as statistics only — there is no
/// LLM/ML budget for real "AI" predictions, so every number here is a
/// plain arithmetic computation over grades/attendance, and the "estimated
/// trend" figure is a linear-trend extrapolation, clearly labeled as an
/// estimate rather than presented as a machine-learning prediction.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  List<Grade> _grades = [];
  List<Attendance> _attendance = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _loading = true);
    try {
      final data = await supabase.from(SupabaseConfig.classesTable).select().order('grade');
      final classes =
          (data as List).map((e) => ClassModel.fromJson(e as Map<String, dynamic>)).toList();
      setState(() => _classes = classes);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final classId = _selectedClass?.id;
      final results = await Future.wait([
        fetchAllRows(() {
          final q = supabase.from(SupabaseConfig.gradesTable).select();
          return (classId == null ? q : q.eq('class_id', classId)).order('id');
        }),
        fetchAllRows(() {
          final q = supabase.from(SupabaseConfig.attendanceTable).select();
          return (classId == null ? q : q.eq('class_id', classId)).order('id');
        }),
      ]);
      setState(() {
        _grades = (results[0] as List).map((e) => Grade.fromJson(e as Map<String, dynamic>)).toList();
        _attendance =
            (results[1] as List).map((e) => Attendance.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjectAverages = AnalyticsService.subjectAverages(_grades);
    final weak = AnalyticsService.weakSubjects(_grades);
    final strong = AnalyticsService.strongSubjects(_grades);
    final attendancePercent = AnalyticsService.attendancePercent(_attendance);
    final averageScore = AnalyticsService.averageScorePercent(_grades);

    final monthlyAverages = <String, List<double>>{};
    for (final g in _grades) {
      final key = DateFormat('yyyy-MM').format(g.gradedAt ?? DateTime.now());
      monthlyAverages.putIfAbsent(key, () => []).add(g.percentage);
    }
    final sortedMonths = monthlyAverages.keys.toList()..sort();
    final trendSeries = [
      for (final m in sortedMonths)
        monthlyAverages[m]!.reduce((a, b) => a + b) / monthlyAverages[m]!.length,
    ];
    final estimatedNext = AnalyticsService.estimatedNextScore(trendSeries);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<ClassModel?>(
                  initialValue: _selectedClass,
                  decoration: const InputDecoration(labelText: 'Class (optional filter)'),
                  items: [
                    const DropdownMenuItem<ClassModel?>(value: null, child: Text('All classes')),
                    ..._classes.map((c) => DropdownMenuItem(value: c, child: Text(c.displayName))),
                  ],
                  onChanged: (c) {
                    setState(() => _selectedClass = c);
                    _loadData();
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statCard('Attendance %', '${attendancePercent.toStringAsFixed(1)}%',
                          Colors.blue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                          'Average Score %', '${averageScore.toStringAsFixed(1)}%', Colors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (estimatedNext != null)
                  Card(
                    color: Colors.amber.withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.trending_up, color: Colors.amber),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Estimated next-exam average trend: ${estimatedNext.toStringAsFixed(1)}% '
                              '(a simple linear-trend estimate from past exam averages, not an AI prediction)',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (subjectAverages.isNotEmpty) ...[
                  Text('Subject-wise average score',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(height: 220, child: _SubjectBarChart(subjects: subjectAverages)),
                  const SizedBox(height: 24),
                ],
                if (strong.isNotEmpty) ...[
                  Text('Strong subjects (≥75% average)',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: strong
                        .map((s) => Chip(
                              label: Text('${s.subjectName} · ${s.averagePercent.toStringAsFixed(0)}%'),
                              backgroundColor: Colors.green.withValues(alpha: 0.1),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                if (weak.isNotEmpty) ...[
                  Text('Weak subjects (<40% average)',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: weak
                        .map((s) => Chip(
                              label: Text('${s.subjectName} · ${s.averagePercent.toStringAsFixed(0)}%'),
                              backgroundColor: Colors.red.withValues(alpha: 0.1),
                            ))
                        .toList(),
                  ),
                ],
                if (_grades.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('No grades recorded yet for this selection')),
                  ),
              ],
            ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _SubjectBarChart extends StatelessWidget {
  const _SubjectBarChart({required this.subjects});
  final List<SubjectPerformance> subjects;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        maxY: 100,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= subjects.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(subjects[idx].subjectName,
                      style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < subjects.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: subjects[i].averagePercent,
                color: subjects[i].averagePercent >= 75
                    ? Colors.green
                    : subjects[i].averagePercent < 40
                        ? Colors.red
                        : Colors.blue,
                width: 18,
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      ),
    );
  }
}
