import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/providers/profile_provider.dart';
import 'package:school_management_app/services/avatar_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Full profile view for a single student or teacher — reachable by admin
/// (from User Management) and by teachers (from My Students). Shows the
/// "ID card" photo, contact details, and role-specific class info: a
/// student's enrolled class, or a teacher's assigned classes.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({super.key, required this.profileId});

  final String profileId;

  @override
  ConsumerState<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  bool _loading = true;
  bool _uploadingPhoto = false;
  Profile? _profile;
  String? _classLabel; // student: their one class. teacher: comma-joined list.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await supabase
          .from(SupabaseConfig.profilesTable)
          .select()
          .eq('id', widget.profileId)
          .single();
      final profile = Profile.fromJson(data);

      String? classLabel;
      if (profile.role == UserRole.student) {
        final enrollment = await supabase
            .from('class_students')
            .select('classes(grade, section, academic_year)')
            .eq('student_id', widget.profileId)
            .maybeSingle();
        final c = enrollment?['classes'] as Map<String, dynamic>?;
        if (c != null) {
          classLabel = 'Grade ${c['grade']} – Section ${c['section']} (${c['academic_year']})';
        }
      } else if (profile.role == UserRole.teacher) {
        final results = await Future.wait([
          supabase
              .from('class_subject_teachers')
              .select('classes(grade, section)')
              .eq('teacher_id', widget.profileId),
          supabase
              .from(SupabaseConfig.classesTable)
              .select('grade, section')
              .eq('teacher_id', widget.profileId),
        ]);
        final labels = <String>{};
        for (final row in results[0] as List) {
          final c = (row as Map<String, dynamic>)['classes'] as Map<String, dynamic>?;
          if (c != null) labels.add('Grade ${c['grade']} – Section ${c['section']}');
        }
        for (final row in results[1] as List) {
          final c = row as Map<String, dynamic>;
          labels.add('Grade ${c['grade']} – Section ${c['section']}');
        }
        classLabel = labels.isEmpty ? null : labels.join(', ');
      }

      setState(() {
        _profile = profile;
        _classLabel = classLabel;
      });
    } catch (e) {
      setState(() => _error = 'Failed to load profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changePhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final url = await AvatarService.pickAndUpload(widget.profileId);
      if (url != null) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _messageOnWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEditPhoto = ref.watch(currentProfileProvider).valueOrNull?.hasAdminPanel ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(_profile?.fullName ?? 'Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 56,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              backgroundImage: _profile!.avatarUrl != null
                                  ? NetworkImage(_profile!.avatarUrl!)
                                  : null,
                              child: _profile!.avatarUrl == null
                                  ? Text(_profile!.fullName[0],
                                      style: const TextStyle(fontSize: 36))
                                  : null,
                            ),
                            if (canEditPhoto)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: InkWell(
                                  onTap: _uploadingPhoto ? null : _changePhoto,
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: theme.colorScheme.primary,
                                    child: _uploadingPhoto
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.camera_alt,
                                            size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(_profile!.fullName,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      Center(
                        child: Text(_profile!.role.name.toUpperCase(),
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: theme.colorScheme.primary)),
                      ),
                      const SizedBox(height: 24),
                      _DetailTile(icon: Icons.email_outlined, label: 'Email', value: _profile!.email),
                      _DetailTile(
                        icon: Icons.phone_outlined,
                        label: 'Mobile number',
                        value: _profile!.phone ?? 'Not on file',
                      ),
                      _DetailTile(
                        icon: Icons.class_outlined,
                        label: _profile!.role == UserRole.teacher
                            ? 'Classes taught'
                            : 'Class',
                        value: _classLabel ?? 'Not assigned yet',
                      ),
                      if (_profile!.phone != null) ...[
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => _messageOnWhatsApp(_profile!.phone!),
                          icon: const Icon(Icons.chat),
                          label: const Text('Message on WhatsApp'),
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label, style: Theme.of(context).textTheme.bodySmall),
        subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
