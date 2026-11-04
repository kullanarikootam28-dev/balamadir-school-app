import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/providers/family_provider.dart';

/// Sits at the top of the student portal when one login covers more than one
/// child (siblings linked by an admin). Shows whose records are on screen and
/// opens a list to switch between them.
class ChildSwitcherCard extends ConsumerWidget {
  const ChildSwitcherCard({super.key, required this.students});

  final List<FamilyStudent> students;

  FamilyStudent _selected(WidgetRef ref) {
    final id = ref.watch(viewedStudentIdProvider) ?? supabase.auth.currentUser?.id;
    final match = students.where((s) => s.id == id);
    return match.isEmpty ? students.first : match.first;
  }

  Widget _avatar(BuildContext context, FamilyStudent student, {double radius = 24}) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: student.avatarUrl != null ? NetworkImage(student.avatarUrl!) : null,
      child: student.avatarUrl == null
          ? Text(student.fullName.isNotEmpty ? student.fullName[0].toUpperCase() : '?',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer))
          : null,
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final selectedId = _selected(ref).id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Choose a child',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            for (final student in students)
              ListTile(
                leading: _avatar(sheetContext, student, radius: 20),
                title: Text(student.fullName),
                subtitle: Text(student.rollNumber == null
                    ? student.classLabel
                    : '${student.classLabel} · Roll ${student.rollNumber}'),
                trailing: student.id == selectedId
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  ref.read(viewedStudentIdProvider.notifier).state = student.id;
                  Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final student = _selected(ref);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPicker(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _avatar(context, student),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Viewing', style: theme.textTheme.bodySmall),
                    Text(student.fullName,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(student.classLabel, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz),
                  Text('Switch', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
