import 'package:school_management_app/models/attendance.dart';
import 'package:school_management_app/models/grade.dart';

/// Statistics-only analytics (no LLM/ML service — no budget for one). Every
/// number here is a plain arithmetic computation over already-fetched
/// grades/attendance rows, and "estimatedNextScore" is a linear-trend
/// extrapolation labeled as an estimate, never presented as an AI
/// prediction.
class SubjectPerformance {
  const SubjectPerformance(this.subjectName, this.averagePercent, this.attemptCount);
  final String subjectName;
  final double averagePercent;
  final int attemptCount;
}

class AnalyticsService {
  AnalyticsService._();

  static List<SubjectPerformance> subjectAverages(List<Grade> grades) {
    final bySubject = <String, List<Grade>>{};
    for (final g in grades) {
      bySubject.putIfAbsent(g.subjectName, () => []).add(g);
    }
    final result = bySubject.entries.map((e) {
      final avg = e.value.map((g) => g.percentage).reduce((a, b) => a + b) / e.value.length;
      return SubjectPerformance(e.key, avg, e.value.length);
    }).toList();
    result.sort((a, b) => b.averagePercent.compareTo(a.averagePercent));
    return result;
  }

  static List<SubjectPerformance> weakSubjects(List<Grade> grades, {double threshold = 40}) =>
      subjectAverages(grades).where((s) => s.averagePercent < threshold).toList();

  static List<SubjectPerformance> strongSubjects(List<Grade> grades, {double threshold = 75}) =>
      subjectAverages(grades).where((s) => s.averagePercent >= threshold).toList();

  static double attendancePercent(List<Attendance> attendance) {
    if (attendance.isEmpty) return 0;
    final present = attendance.fold<double>(0, (sum, a) {
      if (a.status == AttendanceStatus.present || a.status == AttendanceStatus.late) {
        return sum + 1;
      }
      if (a.status == AttendanceStatus.halfDay) return sum + 0.5;
      return sum;
    });
    return present / attendance.length * 100;
  }

  static double averageScorePercent(List<Grade> grades) {
    if (grades.isEmpty) return 0;
    return grades.map((g) => g.percentage).reduce((a, b) => a + b) / grades.length;
  }

  /// A simple least-squares linear trend over exam-ordered average scores.
  /// Returns null when there isn't enough data (fewer than 2 points) to fit
  /// a line. This is arithmetic extrapolation, not a machine-learning
  /// prediction — label it as "estimated trend" wherever it's shown.
  static double? estimatedNextScore(List<double> orderedScores) {
    final n = orderedScores.length;
    if (n < 2) return null;

    final xs = List.generate(n, (i) => i.toDouble());
    final xMean = xs.reduce((a, b) => a + b) / n;
    final yMean = orderedScores.reduce((a, b) => a + b) / n;

    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < n; i++) {
      numerator += (xs[i] - xMean) * (orderedScores[i] - yMean);
      denominator += (xs[i] - xMean) * (xs[i] - xMean);
    }
    if (denominator == 0) return orderedScores.last;

    final slope = numerator / denominator;
    final intercept = yMean - slope * xMean;
    final next = slope * n + intercept;
    return next.clamp(0, 100);
  }
}
