import 'package:flutter/material.dart';

/// A search-filterable single-select list for use inside dialogs, so
/// picking one item out of hundreds (e.g. one student in a 400-500 student
/// school) doesn't mean scrolling a giant DropdownButton menu.
///
/// Typical usage: show this inside a `showDialog` and pop the selection:
/// ```dart
/// final picked = await showDialog<Profile>(
///   context: context,
///   builder: (_) => Dialog(
///     child: Padding(
///       padding: const EdgeInsets.all(16),
///       child: SearchablePicker<Profile>(
///         items: students,
///         labelOf: (s) => s.fullName,
///         onSelected: (s) => Navigator.pop(context, s),
///       ),
///     ),
///   ),
/// );
/// ```
class SearchablePicker<T> extends StatefulWidget {
  const SearchablePicker({
    super.key,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    this.hintText = 'Search by name...',
    this.subtitleOf,
  });

  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T)? subtitleOf;
  final ValueChanged<T> onSelected;
  final String hintText;

  @override
  State<SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<SearchablePicker<T>> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((i) => widget.labelOf(i).toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Text('${filtered.length} of ${widget.items.length}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SizedBox(
          height: 320,
          child: filtered.isEmpty
              ? const Center(child: Text('No matches'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return ListTile(
                      dense: true,
                      title: Text(widget.labelOf(item)),
                      subtitle:
                          widget.subtitleOf != null ? Text(widget.subtitleOf!(item)) : null,
                      onTap: () => widget.onSelected(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
