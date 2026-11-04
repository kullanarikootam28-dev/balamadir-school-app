import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/utils/fetch_all.dart';

class _Student {
  _Student({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.familyId,
    required this.classLabel,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? familyId;
  final String classLabel;
}

/// Links brothers and sisters so one login can switch between them in the
/// student portal. Suggestions come from students who share a parent's phone
/// number — the school still confirms each one, since a shared number isn't
/// proof of a family.
class FamilyLinksScreen extends StatefulWidget {
  const FamilyLinksScreen({super.key});

  @override
  State<FamilyLinksScreen> createState() => _FamilyLinksScreenState();
}

class _FamilyLinksScreenState extends State<FamilyLinksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  bool _working = false;
  List<_Student> _students = [];

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
        fetchAllRows(() => supabase
            .from(SupabaseConfig.profilesTable)
            .select('id, full_name, phone, family_id')
            .eq('role', 'student')
            .order('full_name', ascending: true)
            .order('id')),
        fetchAllRows(() => supabase
            .from('class_students')
            .select('student_id, classes(grade, section)')
            .order('student_id')),
      ]);

      final labels = <String, String>{};
      for (final row in results[1] as List<Map<String, dynamic>>) {
        final cls = row['classes'] as Map?;
        if (cls != null) {
          labels[row['student_id'] as String] = '${cls['grade']}-${cls['section']}';
        }
      }
      setState(() {
        _students = [
          for (final row in results[0] as List<Map<String, dynamic>>)
            _Student(
              id: row['id'] as String,
              fullName: row['full_name'] as String,
              phone: (row['phone'] as String?)?.trim(),
              familyId: row['family_id'] as String?,
              classLabel: labels[row['id']] ?? 'No class',
            ),
        ];
      });
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red));
  }

  /// Students sharing a phone number who aren't already one family.
  List<List<_Student>> get _suggestions {
    final byPhone = <String, List<_Student>>{};
    for (final s in _students) {
      if (s.phone == null || s.phone!.isEmpty) continue;
      byPhone.putIfAbsent(s.phone!, () => []).add(s);
    }
    final out = [
      for (final group in byPhone.values)
        if (group.length > 1 &&
            !(group.every((s) => s.familyId != null) &&
                group.map((s) => s.familyId).toSet().length == 1))
          group,
    ];
    out.sort((a, b) => a.first.fullName.compareTo(b.first.fullName));
    return out;
  }

  Map<String, List<_Student>> get _linkedFamilies {
    final byFamily = <String, List<_Student>>{};
    for (final s in _students) {
      if (s.familyId != null) byFamily.putIfAbsent(s.familyId!, () => []).add(s);
    }
    return byFamily;
  }

  Future<void> _link(List<_Student> group, {bool reload = true}) async {
    await supabase.rpc('admin_link_family',
        params: {'p_student_ids': group.map((s) => s.id).toList()});
    if (reload) await _load();
  }

  Future<void> _unlink(_Student student) async {
    try {
      await supabase.rpc('admin_unlink_student', params: {'p_student_id': student.id});
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _linkOne(List<_Student> group) async {
    setState(() => _working = true);
    try {
      await _link(group);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Linked ${group.map((s) => s.fullName).join(' & ')}')));
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _linkAll() async {
    final groups = _suggestions;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Link all ${groups.length} suggested families?'),
        content: const Text(
            'Each group shares a parent phone number. Linking lets one login switch '
            'between those children. You can unlink any of them afterwards.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Link all')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    var done = 0;
    var failed = 0;
    for (final group in groups) {
      try {
        await _link(group, reload: false);
        done++;
      } catch (_) {
        failed++;
      }
    }
    await _load();
    if (mounted) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Linked $done ${done == 1 ? 'family' : 'families'}'
              '${failed > 0 ? ', $failed could not be linked' : ''}')));
    }
  }

  Future<void> _openManualLink() async {
    final selected = <String>{};
    String query = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final matches = _students
              .where((s) =>
                  query.isEmpty || s.fullName.toLowerCase().contains(query.toLowerCase()))
              .take(40)
              .toList();
          return AlertDialog(
            title: const Text('Link children manually'),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search a student by name...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setDialogState(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final s in matches)
                          CheckboxListTile(
                            dense: true,
                            value: selected.contains(s.id),
                            title: Text(s.fullName),
                            subtitle: Text(
                                '${s.classLabel}${s.familyId != null ? ' · already in a family' : ''}'),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selected.add(s.id);
                              } else {
                                selected.remove(s.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: selected.length < 2
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                        _linkOne(
                            _students.where((s) => selected.contains(s.id)).toList());
                      },
                child: Text('Link ${selected.length} selected'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _groupCard(List<_Student> group, {required bool linked}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    linked
                        ? '${group.length} children share one login'
                        : 'Same phone: ${group.first.phone}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!linked)
                  FilledButton.tonal(
                    onPressed: _working ? null : () => _linkOne(group),
                    child: const Text('Link'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final s in group)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                    radius: 16,
                    child: Text(s.fullName.isNotEmpty ? s.fullName[0] : '?')),
                title: Text(s.fullName),
                subtitle: Text(s.classLabel),
                trailing: linked
                    ? IconButton(
                        icon: const Icon(Icons.link_off, color: Colors.red),
                        tooltip: 'Remove from this family',
                        onPressed: _working ? null : () => _unlink(s),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final families = _linkedFamilies;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Siblings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Suggested (${suggestions.length})'),
            Tab(text: 'Linked (${families.length})'),
          ],
        ),
        actions: [
          if (_working)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                suggestions.isEmpty
                    ? const Center(child: Text('No new sibling suggestions'))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${suggestions.length} groups of students share a parent phone number.',
                                      style: Theme.of(context).textTheme.bodySmall),
                                ),
                                FilledButton.icon(
                                  onPressed: _working ? null : _linkAll,
                                  icon: const Icon(Icons.link, size: 18),
                                  label: const Text('Link all'),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                itemCount: suggestions.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) =>
                                    _groupCard(suggestions[i], linked: false),
                              ),
                            ),
                          ),
                        ],
                      ),
                families.isEmpty
                    ? const Center(child: Text('No families linked yet'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: families.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _groupCard(families.values.elementAt(i), linked: true),
                        ),
                      ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _openManualLink,
        icon: const Icon(Icons.group_add),
        label: const Text('Link manually'),
      ),
    );
  }
}
