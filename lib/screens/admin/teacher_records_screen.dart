import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/models/teacher_details.dart';
import 'package:school_management_app/screens/admin/teacher_record_detail_screen.dart';
import 'package:school_management_app/services/teacher_records_export.dart';
import 'package:school_management_app/utils/error_messages.dart';
import 'package:school_management_app/widgets/export_range_dialog.dart';

enum _SortBy { name, experience, status }

/// Module 2 of the enhancement pass: a dedicated Teacher Records section —
/// searchable/filterable/sortable list, mirroring student_records_screen.dart.
class TeacherRecordsScreen extends StatefulWidget {
  const TeacherRecordsScreen({super.key});

  @override
  State<TeacherRecordsScreen> createState() => _TeacherRecordsScreenState();
}

class _TeacherRecordsScreenState extends State<TeacherRecordsScreen> {
  bool _loading = true;
  List<Profile> _teachers = [];
  final Map<String, TeacherDetails> _detailsByTeacher = {};
  String _query = '';
  TeacherStatus? _statusFilter;
  _SortBy _sortBy = _SortBy.name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'teacher')
            .order('full_name'),
        supabase.from('teacher_details').select(),
      ]);
      final teachers = (results[0] as List)
          .map((e) => Profile.fromJson(e as Map<String, dynamic>))
          .toList();
      _detailsByTeacher.clear();
      for (final row in results[1] as List) {
        final d = TeacherDetails.fromJson(row as Map<String, dynamic>);
        _detailsByTeacher[d.teacherId] = d;
      }
      setState(() => _teachers = teachers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Profile> get _filtered {
    var list = _teachers.where((t) {
      final d = _detailsByTeacher[t.id];
      if (_statusFilter != null && (d?.status ?? TeacherStatus.active) != _statusFilter) {
        return false;
      }
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return t.fullName.toLowerCase().contains(q) ||
          t.email.toLowerCase().contains(q) ||
          (d?.qualification ?? '').toLowerCase().contains(q) ||
          (d?.specialization ?? '').toLowerCase().contains(q);
    }).toList();

    switch (_sortBy) {
      case _SortBy.name:
        list.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case _SortBy.experience:
        list.sort((a, b) => (_detailsByTeacher[b.id]?.experienceYears ?? 0)
            .compareTo(_detailsByTeacher[a.id]?.experienceYears ?? 0));
        break;
      case _SortBy.status:
        list.sort((a, b) => (_detailsByTeacher[a.id]?.status ?? TeacherStatus.active)
            .index
            .compareTo((_detailsByTeacher[b.id]?.status ?? TeacherStatus.active).index));
        break;
    }
    return list;
  }

  Color _statusColor(TeacherStatus s) {
    switch (s) {
      case TeacherStatus.active:
        return Colors.green;
      case TeacherStatus.onLeave:
        return Colors.orange;
      case TeacherStatus.resigned:
        return Colors.grey;
    }
  }

  bool _exporting = false;

  /// Full structured workbook (profiles, attendance by category, monthly
  /// summary, daily log with check-in/out, leaves, assignments) for the
  /// teachers currently shown — the search and status filter apply.
  Future<void> _exportAll() async {
    final range = await showExportRangeDialog(context, title: 'Export teacher records for');
    if (range == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final data = await TeacherRecordsData.load(
        range: range,
        teacherIds: _filtered.map((t) => t.id).toSet(),
      );
      await data.export('teacher_records');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Records'),
        actions: [
          PopupMenuButton<_SortBy>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SortBy.name, child: Text('Sort by name')),
              PopupMenuItem(value: _SortBy.experience, child: Text('Sort by experience')),
              PopupMenuItem(value: _SortBy.status, child: Text('Sort by status')),
            ],
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.table_view_outlined),
            tooltip: 'Export records & attendance (Excel / Google Sheets)',
            onPressed: _teachers.isEmpty || _exporting ? null : _exportAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by name, email, qualification...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('ALL'),
                            selected: _statusFilter == null,
                            onSelected: (_) => setState(() => _statusFilter = null),
                          ),
                        ),
                        for (final s in TeacherStatus.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s.name.toUpperCase()),
                              selected: _statusFilter == s,
                              onSelected: (_) => setState(() => _statusFilter = s),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No teachers found'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final t = filtered[i];
                              final d = _detailsByTeacher[t.id];
                              final status = d?.status ?? TeacherStatus.active;
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                                    child: Text(t.fullName[0]),
                                  ),
                                  title: Text(t.fullName),
                                  subtitle: Text(
                                      '${d?.qualification ?? 'No qualification on file'}${d?.specialization != null ? ' · ${d!.specialization}' : ''}'),
                                  trailing: Text(status.name.toUpperCase(),
                                      style: TextStyle(
                                          color: _statusColor(status), fontWeight: FontWeight.w600, fontSize: 12)),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TeacherRecordDetailScreen(teacher: t),
                                      ),
                                    );
                                    await _load();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
