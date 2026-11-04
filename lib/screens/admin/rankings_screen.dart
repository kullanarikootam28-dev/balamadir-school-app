import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/grade.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/fetch_all.dart';

class _RankedEntry {
  _RankedEntry(this.id, this.name, this.grades);
  final String id;
  final String name;
  final List<Grade> grades;

  double get averagePercent =>
      grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length;

  /// month key (yyyy-MM) -> average % for that month, for a trend line.
  Map<String, double> get monthlyTrend {
    final byMonth = <String, List<Grade>>{};
    for (final g in grades) {
      final date = g.gradedAt ?? DateTime.now();
      final key = DateFormat('yyyy-MM').format(date);
      byMonth.putIfAbsent(key, () => []).add(g);
    }
    final sortedKeys = byMonth.keys.toList()..sort();
    return {
      for (final k in sortedKeys)
        k: byMonth[k]!.map((g) => g.percentage).reduce((a, b) => a + b) / byMonth[k]!.length,
    };
  }
}

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<_RankedEntry> _studentRankings = [];
  List<_RankedEntry> _teacherRankings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        fetchAllRows(() => supabase.from(SupabaseConfig.gradesTable).select().order('id')),
        supabase.from(SupabaseConfig.profilesTable).select().eq('role', 'student'),
        supabase.from(SupabaseConfig.profilesTable).select().eq('role', 'teacher'),
        supabase.from(SupabaseConfig.classesTable).select('id, teacher_id'),
        supabase.from('class_subject_teachers').select('class_id, teacher_id, subjects(name)'),
      ]);

      final grades = (results[0] as List)
          .map((e) => Grade.fromJson(e as Map<String, dynamic>))
          .toList();
      final studentNames = {
        for (final p in results[1] as List) p['id'] as String: p['full_name'] as String,
      };
      final teacherNames = {
        for (final p in results[2] as List) p['id'] as String: p['full_name'] as String,
      };
      final homeroomTeacherByClass = {
        for (final c in results[3] as List)
          c['id'] as String: c['teacher_id'] as String?,
      };
      // (class_id, subject_name) -> teacher_id, from explicit subject assignments.
      final subjectTeacherByClassAndSubject = <String, String>{};
      for (final row in results[4] as List) {
        final classId = row['class_id'] as String;
        final subjectName = (row['subjects'] as Map?)?['name'] as String?;
        final teacherId = row['teacher_id'] as String?;
        if (subjectName != null && teacherId != null) {
          subjectTeacherByClassAndSubject['$classId|$subjectName'] = teacherId;
        }
      }

      // Students
      final gradesByStudent = <String, List<Grade>>{};
      for (final g in grades) {
        gradesByStudent.putIfAbsent(g.studentId, () => []).add(g);
      }
      final studentRankings = gradesByStudent.entries
          .where((e) => studentNames.containsKey(e.key))
          .map((e) => _RankedEntry(e.key, studentNames[e.key]!, e.value))
          .toList()
        ..sort((a, b) => b.averagePercent.compareTo(a.averagePercent));

      // Teachers — attribute each grade to the teacher of that class+subject,
      // falling back to the class's homeroom teacher when no subject-specific
      // assignment exists.
      final gradesByTeacher = <String, List<Grade>>{};
      for (final g in grades) {
        final teacherId = subjectTeacherByClassAndSubject['${g.classId}|${g.subjectName}'] ??
            homeroomTeacherByClass[g.classId];
        if (teacherId == null) continue;
        gradesByTeacher.putIfAbsent(teacherId, () => []).add(g);
      }
      final teacherRankings = gradesByTeacher.entries
          .where((e) => teacherNames.containsKey(e.key))
          .map((e) => _RankedEntry(e.key, teacherNames[e.key]!, e.value))
          .toList()
        ..sort((a, b) => b.averagePercent.compareTo(a.averagePercent));

      setState(() {
        _studentRankings = studentRankings;
        _teacherRankings = teacherRankings;
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

  Future<void> _exportExcel(List<_RankedEntry> entries, String fileBaseName) async {
    try {
      await ExcelExportService.exportRows(
        fileBaseName: fileBaseName,
        headers: const ['Rank', 'Name', 'Average %', 'Grades recorded'],
        rows: [
          for (var i = 0; i < entries.length; i++)
            [i + 1, entries[i].name, entries[i].averagePercent.toStringAsFixed(1), entries[i].grades.length],
        ],
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
    final currentEntries =
        _tabController.index == 1 ? _teacherRankings : _studentRankings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rankings'),
        actions: [
          if (currentEntries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.table_view_outlined),
              tooltip: 'Export Excel',
              onPressed: () => _exportExcel(
                  currentEntries, _tabController.index == 1 ? 'teacher_rankings' : 'student_rankings'),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          onTap: (_) => setState(() {}),
          tabs: const [Tab(text: 'Students'), Tab(text: 'Teachers')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _RankingList(entries: _studentRankings, onRefresh: _load, emptyText: 'No student grades yet'),
                _RankingList(entries: _teacherRankings, onRefresh: _load, emptyText: 'No teacher-attributed grades yet'),
              ],
            ),
    );
  }
}

class _RankingList extends StatelessWidget {
  const _RankingList({required this.entries, required this.onRefresh, required this.emptyText});
  final List<_RankedEntry> entries;
  final Future<void> Function() onRefresh;
  final String emptyText;

  static const _medalColors = [Color(0xFFFFD700), Color(0xFFC0C0C0), Color(0xFFCD7F32)];

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(child: Text(emptyText));
    }
    final top5 = entries.take(5).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (top5.length >= 2) ...[
            Text('Progressive trend (top ${top5.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: _TrendChart(entries: top5)),
            const SizedBox(height: 24),
          ],
          Text('Ranked by average score',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...entries.asMap().entries.map((indexed) {
            final rank = indexed.key;
            final entry = indexed.value;
            final medal = rank < 3 ? _medalColors[rank] : null;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: medal ?? Theme.of(context).colorScheme.primaryContainer,
                  child: Text('${rank + 1}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: medal != null ? Colors.black87 : null)),
                ),
                title: Text(entry.name),
                subtitle: Text('${entry.grades.length} recorded grade(s)'),
                trailing: Text('${entry.averagePercent.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.entries});
  final List<_RankedEntry> entries;

  static const _lineColors = [
    Colors.blue, Colors.red, Colors.green, Colors.orange, Colors.purple,
  ];

  @override
  Widget build(BuildContext context) {
    final allMonths = <String>{};
    for (final e in entries) {
      allMonths.addAll(e.monthlyTrend.keys);
    }
    final months = allMonths.toList()..sort();
    if (months.length < 2) {
      return const Center(child: Text('Not enough history yet for a trend line'));
    }
    final monthIndex = {for (var i = 0; i < months.length; i++) months[i]: i};

    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(DateFormat('MMM').format(DateFormat('yyyy-MM').parse(months[idx])),
                            style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                for (var i = 0; i < entries.length; i++)
                  LineChartBarData(
                    spots: entries[i]
                        .monthlyTrend
                        .entries
                        .map((e) => FlSpot(monthIndex[e.key]!.toDouble(), e.value))
                        .toList()
                      ..sort((a, b) => a.x.compareTo(b.x)),
                    isCurved: true,
                    color: _lineColors[i % _lineColors.length],
                    barWidth: 2.5,
                    dotData: const FlDotData(show: true),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            for (var i = 0; i < entries.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: _lineColors[i % _lineColors.length], shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(entries[i].name, style: const TextStyle(fontSize: 11)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
