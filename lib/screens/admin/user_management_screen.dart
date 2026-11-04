import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/services/admin_user_service.dart';
import 'package:school_management_app/utils/email_check.dart';
import 'package:school_management_app/utils/error_messages.dart';

enum _UserAction { edit, password, delete }

/// Create, edit, re-password and delete accounts. All writes go through
/// [AdminUserService] (admin-checked database functions) — writing to
/// `profiles` directly used to be filtered out by row-level security, which
/// is why Edit and Delete silently did nothing.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<Profile> _profiles = [];
  String _searchQuery = '';

  static const _tabs = [null, UserRole.student, UserRole.teacher, UserRole.admin];

  String? get _myId => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _fetchProfiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfiles() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from(SupabaseConfig.profilesTable)
          .select()
          .order('full_name');
      setState(() {
        _profiles = (data as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object e, [BuildContext? ctx]) {
    final c = ctx ?? context;
    if (!c.mounted) return;
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: Colors.red),
    );
  }

  void _showDone(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Profile> _forRole(UserRole? role) {
    final base = switch (role) {
      null => _profiles,
      // Teachers with admin access show under Admins as well.
      UserRole.admin => _profiles.where((p) => p.hasAdminPanel),
      _ => _profiles.where((p) => p.role == role),
    };
    if (_searchQuery.isEmpty) return base.toList();
    final q = _searchQuery.toLowerCase();
    return base
        .where((p) =>
            p.fullName.toLowerCase().contains(q) || p.email.toLowerCase().contains(q))
        .toList();
  }

  static String _generatePassword() {
    // No look-alike characters (0/O, 1/l/I) — it gets read out or typed by hand.
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Widget _adminAccessSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: enabled ? onChanged : null,
        title: const Text('Also give Admin panel access'),
        subtitle: const Text(
            'Same email and password. At sign-in they choose Admin or Teacher, and can switch any time.'),
      );

  // ── Create ────────────────────────────────────────────────────────────────
  Future<void> _openCreateDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    UserRole role = UserRole.student;
    bool adminAccess = false;
    bool obscure = true;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Register Account'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: validateAccountEmail,
                  ),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  ),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Initial password',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: obscure ? 'Show' : 'Hide',
                            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setDialogState(() => obscure = !obscure),
                          ),
                          IconButton(
                            tooltip: 'Generate a password',
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed: () => setDialogState(() {
                              passwordCtrl.text = _generatePassword();
                              obscure = false;
                            }),
                          ),
                        ],
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.trim().length < 6 ? 'Min 6 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: UserRole.values
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r.name.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setDialogState(() => role = v!),
                  ),
                  if (role == UserRole.teacher)
                    _adminAccessSwitch(
                      value: adminAccess,
                      onChanged: (v) => setDialogState(() => adminAccess = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => submitting = true);
                      try {
                        await AdminUserService.registerUser(
                          email: emailCtrl.text.trim(),
                          password: passwordCtrl.text.trim(),
                          fullName: nameCtrl.text.trim(),
                          role: role,
                          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                          adminAccess: adminAccess,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        _showDone('Account created for ${nameCtrl.text.trim()}');
                        await _fetchProfiles();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        if (dialogContext.mounted) _showError(e, dialogContext);
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit ──────────────────────────────────────────────────────────────────
  Future<void> _openEditDialog(Profile profile) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: profile.fullName);
    final phoneCtrl = TextEditingController(text: profile.phone ?? '');
    UserRole role = profile.role;
    bool adminAccess = profile.adminAccess;
    bool saving = false;
    final isMe = profile.id == _myId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Edit ${profile.fullName}'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.email, style: Theme.of(dialogContext).textTheme.bodySmall),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: UserRole.values
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r.name.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setDialogState(() => role = v!),
                  ),
                  if (role == UserRole.teacher)
                    _adminAccessSwitch(
                      value: adminAccess,
                      onChanged: (v) => setDialogState(() => adminAccess = v),
                    ),
                  if (isMe && profile.hasAdminPanel)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This is your own account — you can\'t remove your own admin access.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      try {
                        await AdminUserService.updateUser(
                          userId: profile.id,
                          fullName: nameCtrl.text.trim(),
                          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                          role: role,
                          adminAccess: adminAccess,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        _showDone('Saved changes to ${nameCtrl.text.trim()}');
                        await _fetchProfiles();
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (dialogContext.mounted) _showError(e, dialogContext);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Set password ──────────────────────────────────────────────────────────
  Future<void> _openPasswordDialog(Profile profile) async {
    final formKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    bool saving = false;
    final isMe = profile.id == _myId;

    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Set password for ${profile.fullName}'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.email, style: Theme.of(dialogContext).textTheme.bodySmall),
                  TextFormField(
                    controller: passCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: obscure ? 'Show' : 'Hide',
                            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setDialogState(() => obscure = !obscure),
                          ),
                          IconButton(
                            tooltip: 'Generate a password',
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed: () => setDialogState(() {
                              final generated = _generatePassword();
                              passCtrl.text = generated;
                              confirmCtrl.text = generated;
                              obscure = false;
                            }),
                          ),
                        ],
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.trim().length < 6 ? 'Min 6 characters' : null,
                  ),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    decoration: const InputDecoration(labelText: 'Type it again'),
                    validator: (v) =>
                        v?.trim() != passCtrl.text.trim() ? 'Passwords don\'t match' : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isMe
                        ? 'This changes your own password.'
                        : 'Their old password stops working and they\'re signed out of '
                            'their other devices.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      final password = passCtrl.text.trim();
                      try {
                        await AdminUserService.setPassword(
                            userId: profile.id, password: password);
                        if (dialogContext.mounted) Navigator.pop(dialogContext, password);
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (dialogContext.mounted) _showError(e, dialogContext);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Set password'),
            ),
          ],
        ),
      ),
    );

    if (newPassword == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
        title: const Text('Password updated'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share these with ${profile.fullName}:'),
            const SizedBox(height: 12),
            SelectableText('Email: ${profile.email}\nPassword: $newPassword',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: 'Email: ${profile.email}\nPassword: $newPassword'));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _confirmDelete(Profile profile) async {
    final whatGoes = switch (profile.role) {
      UserRole.student =>
        'their attendance, marks, fee records, class enrollment, transport and messages',
      UserRole.teacher =>
        'their attendance and leave records, class/subject assignments, notices they posted and messages',
      UserRole.admin => 'their messages and notices they posted',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
        title: Text('Delete ${profile.fullName}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.email, style: Theme.of(dialogContext).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text('This permanently deletes the login and $whatGoes. It can\'t be undone.'),
            if (profile.role == UserRole.student) ...[
              const SizedBox(height: 12),
              const Text(
                'To keep a student\'s history, set their status to Transferred or '
                'Archived in Student Records instead.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminUserService.deleteUser(profile.id);
      _showDone('${profile.fullName} was deleted');
      await _fetchProfiles();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _onAction(_UserAction action, Profile p) async {
    switch (action) {
      case _UserAction.edit:
        await _openEditDialog(p);
      case _UserAction.password:
        await _openPasswordDialog(p);
      case _UserAction.delete:
        await _confirmDelete(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Students'),
            Tab(text: 'Teachers'),
            Tab(text: 'Admins'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by name or email...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: _tabs.map((role) {
                      final list = _forRole(role);
                      if (list.isEmpty) {
                        return Center(
                            child: Text(_searchQuery.isEmpty
                                ? 'No accounts yet'
                                : 'No matches for "$_searchQuery"'));
                      }
                      return RefreshIndicator(
                        onRefresh: _fetchProfiles,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final p = list[i];
                            final isMe = p.id == _myId;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage:
                                      p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
                                  child: p.avatarUrl == null
                                      ? Text(p.fullName.isNotEmpty ? p.fullName[0] : '?')
                                      : null,
                                ),
                                title: Text(isMe ? '${p.fullName} (you)' : p.fullName),
                                subtitle: Text('${p.email}\n${p.roleLabel}'),
                                isThreeLine: true,
                                onTap: () => context.push('/profile/${p.id}'),
                                trailing: PopupMenuButton<_UserAction>(
                                  tooltip: 'Account options',
                                  onSelected: (a) => _onAction(a, p),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: _UserAction.edit,
                                      child: ListTile(
                                          leading: Icon(Icons.edit_outlined),
                                          title: Text('Edit role & details')),
                                    ),
                                    const PopupMenuItem(
                                      value: _UserAction.password,
                                      child: ListTile(
                                          leading: Icon(Icons.key_outlined),
                                          title: Text('Set new password')),
                                    ),
                                    if (!isMe)
                                      const PopupMenuItem(
                                        value: _UserAction.delete,
                                        child: ListTile(
                                          leading: Icon(Icons.delete_outline, color: Colors.red),
                                          title: Text('Delete account',
                                              style: TextStyle(color: Colors.red)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Register'),
      ),
    );
  }
}
