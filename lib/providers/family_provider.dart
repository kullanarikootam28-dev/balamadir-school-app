import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/providers/auth_provider.dart';

/// One child a login can open in the student portal.
class FamilyStudent {
  const FamilyStudent({
    required this.id,
    required this.fullName,
    required this.isSelf,
    this.avatarUrl,
    this.grade,
    this.section,
    this.rollNumber,
  });

  final String id;
  final String fullName;
  final bool isSelf;
  final String? avatarUrl;
  final String? grade;
  final String? section;
  final String? rollNumber;

  String get classLabel => grade == null ? 'No class assigned' : '$grade-$section';

  /// First name, for tight spaces like an app bar title.
  String get shortName => fullName.trim().split(RegExp(r'\s+')).first;

  factory FamilyStudent.fromRow(Map<String, dynamic> row) => FamilyStudent(
        id: row['id'] as String,
        fullName: row['full_name'] as String,
        isSelf: row['is_self'] as bool? ?? false,
        avatarUrl: row['avatar_url'] as String?,
        grade: row['grade'] as String?,
        section: row['section'] as String?,
        rollNumber: row['roll_number'] as String?,
      );
}

/// The children this login may open: itself, plus any siblings an admin has
/// linked to it (migration 027). One entry for a student with no siblings
/// linked, so the switcher simply doesn't appear.
final familyStudentsProvider = FutureProvider<List<FamilyStudent>>((ref) async {
  ref.watch(currentUserIdProvider
      .select((v) => v.valueOrNull ?? supabase.auth.currentUser?.id));
  if (supabase.auth.currentUser == null) return const [];
  final rows = await supabase.rpc('my_family_students');
  return [
    for (final row in (rows as List)) FamilyStudent.fromRow(row as Map<String, dynamic>),
  ];
});

/// Which child the student portal is showing. Null means the logged-in
/// account itself; resets when a different account signs in.
final viewedStudentIdProvider = StateProvider<String?>((ref) {
  ref.watch(currentUserIdProvider.select((v) => v.valueOrNull));
  return null;
});

extension ViewedStudentRef on WidgetRef {
  /// The child whose records the portal should load. Safe outside build.
  String get viewedStudentId =>
      read(viewedStudentIdProvider) ?? supabase.auth.currentUser!.id;

  /// Adds the child's name to a screen title while a family is switching
  /// between children, so it's always clear whose records are on screen.
  String familyTitle(String base) {
    final students = watch(familyStudentsProvider).valueOrNull;
    if (students == null || students.length < 2) return base;
    final id = watch(viewedStudentIdProvider) ?? supabase.auth.currentUser?.id;
    final current = students.where((s) => s.id == id);
    if (current.isEmpty) return base;
    return '$base · ${current.first.shortName}';
  }
}
