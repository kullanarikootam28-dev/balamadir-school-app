import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 20 of the client spec: search by Student Name, Admission Number,
/// EMIS Number, Roll Number, Parent Name, Teacher Name, or Mobile Number —
/// all in one box, querying profiles/student_details/class_students in
/// parallel.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _SearchHit {
  const _SearchHit({
    required this.profileId,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String profileId;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  bool _searching = false;
  List<_SearchHit> _results = [];
  String _lastQuery = '';

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _lastQuery = '';
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await Future.wait([
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .or('full_name.ilike.%$q%,phone.ilike.%$q%,email.ilike.%$q%'),
        supabase
            .from('student_details')
            .select('student_id, admission_number, emis_id, father_name, mother_name, profiles(full_name, email)')
            .or('admission_number.ilike.%$q%,emis_id.ilike.%$q%,father_name.ilike.%$q%,mother_name.ilike.%$q%'),
        supabase
            .from('class_students')
            .select('student_id, roll_number, profiles(full_name, email)')
            .ilike('roll_number', '%$q%'),
      ]);

      final hits = <String, _SearchHit>{};

      for (final row in (results[0] as List)) {
        final r = row as Map<String, dynamic>;
        hits[r['id'] as String] = _SearchHit(
          profileId: r['id'] as String,
          title: r['full_name'] as String,
          subtitle: '${(r['role'] as String).toUpperCase()} · ${r['email']}${r['phone'] != null ? ' · ${r['phone']}' : ''}',
          icon: Icons.person_outline,
        );
      }

      for (final row in (results[1] as List)) {
        final r = row as Map<String, dynamic>;
        final profile = r['profiles'] as Map?;
        if (profile == null) continue;
        hits[r['student_id'] as String] = _SearchHit(
          profileId: r['student_id'] as String,
          title: profile['full_name'] as String,
          subtitle:
              'Admission #${r['admission_number'] ?? '—'} · EMIS ${r['emis_id'] ?? '—'}${r['father_name'] != null ? ' · Father: ${r['father_name']}' : ''}',
          icon: Icons.badge_outlined,
        );
      }

      for (final row in (results[2] as List)) {
        final r = row as Map<String, dynamic>;
        final profile = r['profiles'] as Map?;
        if (profile == null) continue;
        hits[r['student_id'] as String] = _SearchHit(
          profileId: r['student_id'] as String,
          title: profile['full_name'] as String,
          subtitle: 'Roll number ${r['roll_number']}',
          icon: Icons.numbers,
        );
      }

      setState(() {
        _results = hits.values.toList();
        _lastQuery = q;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Name, admission no., EMIS, roll no., mobile...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              onSubmitted: _search,
              onChanged: (v) {
                if (v.trim().length >= 3) _search(v);
              },
            ),
          ),
          Expanded(
            child: _lastQuery.isEmpty
                ? const Center(child: Text('Type at least 3 characters to search'))
                : _results.isEmpty
                    ? Center(child: Text('No matches for "$_lastQuery"'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          return Card(
                            child: ListTile(
                              leading: Icon(r.icon),
                              title: Text(r.title),
                              subtitle: Text(r.subtitle),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/profile/${r.profileId}'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
