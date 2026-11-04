import 'package:flutter/material.dart';

import 'package:school_management_app/providers/family_provider.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/providers/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_management_app/utils/error_messages.dart';

class ProfileOverviewScreen extends ConsumerStatefulWidget {
  const ProfileOverviewScreen({super.key});

  @override
  ConsumerState<ProfileOverviewScreen> createState() => _ProfileOverviewScreenState();
}

class _ProfileOverviewScreenState extends ConsumerState<ProfileOverviewScreen> {
  bool _loading = true;
  Map<String, dynamic>? _enrollment; // roll_number, classes(*)
  Map<String, dynamic>? _transport; // buses(*), bus_stops(*)
  Map<String, dynamic>? _studentProfile; // the child being viewed

  @override
  void initState() {
    super.initState();
    _loadEnrollment();
    _loadTransport();
    _loadStudentProfile();
  }

  Future<void> _loadEnrollment() async {
    setState(() => _loading = true);
    try {
      final studentId = ref.viewedStudentId;
      final data = await supabase
          .from('class_students')
          .select('roll_number, classes(grade, section, academic_year)')
          .eq('student_id', studentId)
          .maybeSingle();
      setState(() => _enrollment = data);
    } catch (_) {
      // no enrollment yet — leave null, screen shows "not enrolled" state
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The switcher can be showing a sibling, so the name/email/phone on this
  /// page come from that child's profile rather than the signed-in account.
  Future<void> _loadStudentProfile() async {
    try {
      final data = await supabase
          .from('profiles')
          .select('full_name, email, phone, avatar_url')
          .eq('id', ref.viewedStudentId)
          .maybeSingle();
      if (mounted) setState(() => _studentProfile = data);
    } catch (_) {
      // Falls back to the signed-in account's own profile below.
    }
  }

  Future<void> _loadTransport() async {
    try {
      final studentId = ref.viewedStudentId;
      final data = await supabase
          .from('student_transport')
          .select('buses(bus_number, route, driver_name, driver_contact), '
              'bus_stops(stop_name, pickup_time, drop_time)')
          .eq('student_id', studentId)
          .maybeSingle();
      if (mounted) setState(() => _transport = data);
    } catch (_) {
      // no assignment yet — leave null, section is simply omitted
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viewedStudentIdProvider, (_, __) => _loadEnrollment());
    ref.listen(viewedStudentIdProvider, (_, __) => _loadTransport());
    ref.listen(viewedStudentIdProvider, (_, __) => _loadStudentProfile());
    final profileAsync = ref.watch(currentProfileProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile Overview')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(friendlyErrorMessage(e))),
              data: (profile) {
                final classInfo = _enrollment?['classes'] as Map<String, dynamic>?;
                final viewed = _studentProfile;
                final fullName = viewed?['full_name'] as String? ?? profile.fullName;
                final email = viewed?['email'] as String? ?? profile.email;
                final phone = viewed?['phone'] as String? ?? profile.phone;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          fullName.isNotEmpty ? fullName[0] : '?',
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(fullName,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Center(
                      child: Text(profile.role.name.toUpperCase(),
                          style: theme.textTheme.bodySmall),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.email_outlined),
                            title: const Text('Email'),
                            subtitle: Text(email),
                          ),
                          if (phone != null)
                            ListTile(
                              leading: const Icon(Icons.phone_outlined),
                              title: const Text('Phone'),
                              subtitle: Text(phone),
                            ),
                          ListTile(
                            leading: const Icon(Icons.confirmation_number_outlined),
                            title: const Text('Roll Number'),
                            subtitle: Text(
                                _enrollment?['roll_number'] as String? ?? 'Not assigned yet'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.class_outlined),
                            title: const Text('Class'),
                            subtitle: Text(
                              classInfo == null
                                  ? 'Not enrolled in a class yet'
                                  : 'Grade ${classInfo['grade']} – Section ${classInfo['section']} (${classInfo['academic_year']})',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_transport != null &&
                        (_transport!['buses'] != null || _transport!['bus_stops'] != null)) ...[
                      const SizedBox(height: 16),
                      Card(
                        child: Column(
                          children: [
                            const ListTile(
                              leading: Icon(Icons.directions_bus_outlined),
                              title: Text('Transport', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            if (_transport!['buses'] != null)
                              ListTile(
                                leading: const Icon(Icons.confirmation_num_outlined),
                                title: const Text('Bus'),
                                subtitle: Text(
                                    'Bus ${(_transport!['buses'] as Map)['bus_number']}'
                                    '${(_transport!['buses'] as Map)['route'] != null ? ' · ${(_transport!['buses'] as Map)['route']}' : ''}'),
                              ),
                            if (_transport!['bus_stops'] != null)
                              ListTile(
                                leading: const Icon(Icons.location_on_outlined),
                                title: const Text('Stop'),
                                subtitle: Text(_stopSubtitle(_transport!['bus_stops'] as Map)),
                              ),
                            if (_transport!['buses'] != null &&
                                (_transport!['buses'] as Map)['driver_name'] != null)
                              ListTile(
                                leading: const Icon(Icons.person_outline),
                                title: const Text('Driver'),
                                subtitle: Text(
                                    '${(_transport!['buses'] as Map)['driver_name']}'
                                    '${(_transport!['buses'] as Map)['driver_contact'] != null ? ' · ${(_transport!['buses'] as Map)['driver_contact']}' : ''}'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  String _stopSubtitle(Map stop) {
    final parts = <String>[stop['stop_name'] as String];
    if (stop['pickup_time'] != null) parts.add('Pickup ${stop['pickup_time']}');
    if (stop['drop_time'] != null) parts.add('Drop ${stop['drop_time']}');
    return parts.join(' · ');
  }
}
