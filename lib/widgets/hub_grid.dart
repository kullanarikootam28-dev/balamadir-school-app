import 'package:flutter/material.dart';

/// One round, colour-coded shortcut in the hub grid — the school-app look:
/// a filled circle with a white glyph and the name underneath.
class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Small count bubble (unread messages, pending items).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.surface, width: 2),
                    ),
                    child: Text(badge! > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Lays the shortcuts out three-per-row on a phone, wider on a PC window.
class HubGrid extends StatelessWidget {
  const HubGrid({super.key, required this.children});

  final List<Widget> children;

  int _columnsFor(double width) {
    if (width < 420) return 3;
    if (width < 700) return 4;
    if (width < 1100) return 6;
    return 8;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        crossAxisCount: _columnsFor(constraints.maxWidth),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 18,
        childAspectRatio: 0.82,
        children: children,
      ),
    );
  }
}

/// Section label above a hub grid ("School Hub", "Academics"...).
class HubSectionTitle extends StatelessWidget {
  const HubSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}
