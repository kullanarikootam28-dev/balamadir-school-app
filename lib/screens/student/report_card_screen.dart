import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/grade.dart';
import 'package:school_management_app/services/report_card_pdf_service.dart';
import 'package:school_management_app/utils/subject_colors.dart';
import 'package:school_management_app/utils/error_messages.dart';

class _SubjectSummary {
  _SubjectSummary(this.subjectName, this.grades);
  final String subjectName;
  final List<Grade> grades;

  double get averagePercent =>
      grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length;
}

String _tierFor(double percent) {
  if (percent >= 90) return 'A+';
  if (percent >= 80) return 'A';
  if (percent >= 70) return 'B';
  if (percent >= 60) return 'C';
  if (percent >= 50) return 'D';
  return 'F';
}

class ReportCardScreen extends ConsumerStatefulWidget {
  const ReportCardScreen({super.key});

  @override
  ConsumerState<ReportCardScreen> createState() => _ReportCardScreenState();
}

class _ReportCardScreenState extends ConsumerState<ReportCardScreen> {
  bool _loading = true;
  bool _downloading = false;
  List<Grade> _grades = [];
  String _studentName = '';
  String _className = '—';
  int? _rank;
  int? _totalInClass;
  String? _remarks;

  @override
  void initState() {
    super.initState();
    _fetchGrades();
  }

  Future<void> _fetchGrades() async {
    setState(() => _loading = true);
    try {
      final userId = ref.viewedStudentId;
      final results = await Future.wait([
        supabase
            .from(SupabaseConfig.gradesTable)
            .select('*, classes(grade, section)')
            .eq('student_id', userId as Object)
            .order('graded_at', ascending: false),
        supabase
            .from(SupabaseConfig.profilesTable)
            .select('full_name')
            .eq('id', userId as Object)
            .single(),
      ]);
      final grades = (results[0] as List)
          .map((e) => Grade.fromJson(e as Map<String, dynamic>))
          .toList();
      String className = '—';
      String? classId;
      if (grades.isNotEmpty) {
        classId = grades.first.classId;
        className = 'Grade ${grades.first.classId}';
      }
      setState(() {
        _grades = grades;
        _studentName = (results[1] as Map<String, dynamic>)['full_name'] as String? ?? '';
      });
      if (grades.isNotEmpty) {
        final classRow = await supabase
            .from(SupabaseConfig.classesTable)
            .select('grade, section')
            .eq('id', grades.first.classId)
            .maybeSingle();
        if (classRow != null) {
          className = 'Grade ${classRow['grade']} – ${classRow['section']}';
        }
        setState(() => _className = className);
        await _computeRank(userId, classId!);
        await _loadRemarks(userId);
      }
    } catch (_) {
      // leave list empty — screen shows an empty state
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Class rank by overall average percentage across all recorded grades,
  /// computed the same way as admin/rankings_screen.dart's student ranking.
  Future<void> _computeRank(String userId, String classId) async {
    try {
      final data = await supabase
          .from(SupabaseConfig.gradesTable)
          .select('student_id, score, max_score')
          .eq('class_id', classId);
      final byStudent = <String, List<double>>{};
      for (final row in (data as List)) {
        final r = row as Map<String, dynamic>;
        final percent = (r['score'] as num) / (r['max_score'] as num) * 100;
        byStudent.putIfAbsent(r['student_id'] as String, () => []).add(percent.toDouble());
      }
      final averages = byStudent.entries
          .map((e) => MapEntry(e.key, e.value.reduce((a, b) => a + b) / e.value.length))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final rank = averages.indexWhere((e) => e.key == userId) + 1;
      if (rank > 0) {
        setState(() {
          _rank = rank;
          _totalInClass = averages.length;
        });
      }
    } catch (_) {
      // Rank is a nice-to-have; leave it unset on failure.
    }
  }

  Future<void> _loadRemarks(String userId) async {
    try {
      final data = await supabase
          .from('report_card_remarks')
          .select('remarks')
          .eq('student_id', userId)
          .not('remarks', 'is', null)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data != null) {
        setState(() => _remarks = data['remarks'] as String?);
      }
    } catch (_) {
      // No remarks yet — fine to leave null.
    }
  }

  Future<void> _downloadPdf() async {
    setState(() => _downloading = true);
    try {
      await ReportCardPdfService.downloadReportCard(
        studentName: _studentName,
        className: _className,
        grades: _grades,
        overallPercent: _overallPercent,
        overallGrade: _tierFor(_overallPercent),
        rank: _rank,
        totalInClass: _totalInClass,
        remarks: _remarks,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  List<_SubjectSummary> get _bySubject {
    final map = <String, List<Grade>>{};
    for (final g in _grades) {
      map.putIfAbsent(g.subjectName, () => []).add(g);
    }
    return map.entries.map((e) => _SubjectSummary(e.key, e.value)).toList();
  }

  double get _overallPercent {
    if (_grades.isEmpty) return 0;
    return _grades.map((g) => g.percentage).reduce((a, b) => a + b) / _grades.length;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _fetchGrades());
    final subjects = _bySubject;
    final overall = _overallPercent;

    return Scaffold(
      appBar: AppBar(
        title: Text(ref.familyTitle('Academic Report Card')),
        actions: [
          if (_grades.isNotEmpty)
            IconButton(
              icon: _downloading
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Download PDF',
              onPressed: _downloading ? null : _downloadPdf,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _grades.isEmpty
              ? const Center(child: Text('No grades recorded yet'))
              : RefreshIndicator(
                  onRefresh: _fetchGrades,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _OverallTierCard(
                        overallPercent: overall,
                        subjectCount: subjects.length,
                        rank: _rank,
                        totalInClass: _totalInClass,
                      ),
                      if (_remarks != null && _remarks!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: Colors.blue.withValues(alpha: 0.08),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Teacher remarks',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(_remarks!),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (subjects.length >= 3) ...[
                        Text('Subject Performance',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 240,
                          child: RadarChart(
                            RadarChartData(
                              radarShape: RadarShape.polygon,
                              tickCount: 4,
                              ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 0),
                              radarBorderData: BorderSide(color: Theme.of(context).dividerColor),
                              gridBorderData: BorderSide(color: Theme.of(context).dividerColor),
                              titleTextStyle: Theme.of(context).textTheme.labelSmall,
                              getTitle: (index, angle) => RadarChartTitle(
                                text: subjects[index % subjects.length].subjectName,
                              ),
                              dataSets: [
                                RadarDataSet(
                                  fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                  borderColor: Theme.of(context).colorScheme.primary,
                                  dataEntries: subjects
                                      .map((s) => RadarEntry(value: s.averagePercent))
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text('Subjects',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...subjects.map((s) => _SubjectCard(summary: s)),
                    ],
                  ),
                ),
    );
  }
}

class _OverallTierCard extends StatelessWidget {
  const _OverallTierCard({
    required this.overallPercent,
    required this.subjectCount,
    this.rank,
    this.totalInClass,
  });
  final double overallPercent;
  final int subjectCount;
  final int? rank;
  final int? totalInClass;

  @override
  Widget build(BuildContext context) {
    final tier = _tierFor(overallPercent);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(tier,
                style: theme.textTheme.displayMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            Text('Overall · ${overallPercent.toStringAsFixed(1)}%',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text('$subjectCount subject${subjectCount == 1 ? '' : 's'} recorded',
                style: theme.textTheme.bodySmall),
            if (rank != null && totalInClass != null) ...[
              const SizedBox(height: 8),
              Text('Class rank: $rank of $totalInClass',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.summary});
  final _SubjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final color = subjectColor(summary.subjectName);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(summary.subjectName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_tierFor(summary.averagePercent),
                      style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (summary.averagePercent / 100).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 6),
              ...summary.grades.map((g) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${g.examType ?? 'Exam'}'
                          '${g.gradedAt != null ? ' · ${DateFormat.yMMMd().format(g.gradedAt!)}' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text('${g.score.toStringAsFixed(0)}/${g.maxScore.toStringAsFixed(0)}'),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
