import 'package:flutter/material.dart';

import 'package:school_management_app/models/timetable_slot.dart';

/// Renders a weekly timetable as a day-by-period grid. Used read-only by
/// teacher/student timetable screens and in editable mode by the admin's
/// timetable setup screen (pass [onCellTap] to make cells tappable).
class TimetableGrid extends StatelessWidget {
  const TimetableGrid({
    super.key,
    required this.slots,
    this.periodsCount = 8,
    this.daysCount = 6, // Monday..Saturday
    this.onCellTap,
  });

  final List<TimetableSlot> slots;
  final int periodsCount;
  final int daysCount;
  final void Function(int dayOfWeek, int periodNumber, TimetableSlot? slot)?
      onCellTap;

  TimetableSlot? _slotFor(int day, int period) {
    for (final s in slots) {
      if (s.dayOfWeek == day && s.periodNumber == period) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cellWidth = 120.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: theme.dividerColor, width: 0.5),
          defaultColumnWidth: const FixedColumnWidth(cellWidth),
          children: [
            TableRow(
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
              children: [
                const _HeaderCell('Period'),
                for (var d = 1; d <= daysCount; d++)
                  _HeaderCell(kWeekdayNames[d - 1].substring(0, 3)),
              ],
            ),
            for (var p = 1; p <= periodsCount; p++)
              TableRow(
                children: [
                  _HeaderCell('P$p'),
                  for (var d = 1; d <= daysCount; d++)
                    _SlotCell(
                      slot: _slotFor(d, p),
                      onTap: onCellTap == null
                          ? null
                          : () => onCellTap!(d, p, _slotFor(d, p)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SlotCell extends StatelessWidget {
  const _SlotCell({required this.slot, this.onTap});
  final TimetableSlot? slot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        alignment: Alignment.center,
        child: slot == null
            ? (onTap != null
                ? Icon(Icons.add, size: 16, color: theme.disabledColor)
                : const Text('—'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slot!.subjectName ?? '—',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (slot!.className != null)
                    Text(
                      slot!.className!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    )
                  else if (slot!.teacherName != null)
                    Text(
                      slot!.teacherName!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
      ),
    );
  }
}
