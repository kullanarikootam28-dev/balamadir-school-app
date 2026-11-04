import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:school_management_app/main.dart';
import 'package:school_management_app/utils/error_messages.dart';

const _kTokenLifetime = Duration(seconds: 10);
const _kTokenChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

String _generateToken() {
  final rand = Random.secure();
  final random = List.generate(32, (_) => _kTokenChars[rand.nextInt(_kTokenChars.length)]).join();
  return 'SCHOOL_${random}_${DateTime.now().millisecondsSinceEpoch}';
}

/// Module 3 of the enhancement pass: admin opens this on a desktop browser
/// (Flutter Web), a rotating QR code is shown, and any teacher who scans it
/// with the app within its 10-second window is marked present. See
/// 015_qr_attendance.sql for the server-side verification this relies on —
/// this screen only ever writes the *current* token, never marks attendance
/// itself.
class DailyAttendancePortalScreen extends StatefulWidget {
  const DailyAttendancePortalScreen({super.key});

  @override
  State<DailyAttendancePortalScreen> createState() => _DailyAttendancePortalScreenState();
}

class _DailyAttendancePortalScreenState extends State<DailyAttendancePortalScreen> {
  String _token = '';
  DateTime _generatedAt = DateTime.now();
  Timer? _rotateTimer;
  Timer? _countdownTimer;
  int _secondsLeft = _kTokenLifetime.inSeconds;
  List<Map<String, dynamic>> _presentToday = [];
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _rotate();
    _rotateTimer = Timer.periodic(_kTokenLifetime, (_) => _rotate());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = DateTime.now().difference(_generatedAt).inSeconds;
      final left = _kTokenLifetime.inSeconds - elapsed;
      if (mounted) setState(() => _secondsLeft = left < 0 ? 0 : left);
    });
    _loadPresentToday();
    _subscribe();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _countdownTimer?.cancel();
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _rotate() async {
    final token = _generateToken();
    try {
      await supabase.from('live_qr_gate').update({
        'token': token,
        'generated_at': DateTime.now().toIso8601String(),
        'generated_by': supabase.auth.currentUser?.id,
      }).eq('id', 'default');
      if (mounted) {
        setState(() {
          _token = token;
          _generatedAt = DateTime.now();
          _secondsLeft = _kTokenLifetime.inSeconds;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _loadPresentToday() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final data = await supabase
        .from('teacher_attendance')
        .select(
            'teacher_id, created_at, check_in_time, check_out_time, profiles!teacher_attendance_teacher_id_fkey(full_name)')
        .eq('date', today)
        .eq('status', 'present')
        .order('created_at', ascending: false);
    if (mounted) setState(() => _presentToday = List<Map<String, dynamic>>.from(data));
  }

  void _subscribe() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _channel = supabase
        .channel('teacher_attendance_live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'teacher_attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'date',
            value: today,
          ),
          callback: (_) => _loadPresentToday(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsLeft / _kTokenLifetime.inSeconds;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Attendance Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Scan log',
            onPressed: () => context.push('/admin/qr-scan-log'),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Scan to check in', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
                    ),
                    child: _token.isEmpty
                        ? const SizedBox(width: 260, height: 260)
                        : QrImageView(data: _token, size: 260, backgroundColor: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(value: progress.clamp(0, 1)),
                  ),
                  const SizedBox(height: 8),
                  Text('Refreshes in ${_secondsLeft}s',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Code rotates automatically every ${_kTokenLifetime.inSeconds} seconds',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Checked in today (${_presentToday.length})',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _presentToday.isEmpty
                        ? const Center(child: Text('No check-ins yet'))
                        : ListView.separated(
                            itemCount: _presentToday.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final row = _presentToday[i];
                              final name =
                                  (row['profiles'] as Map?)?['full_name'] as String? ?? '—';
                              final checkIn = row['check_in_time'] != null
                                  ? DateFormat('h:mm:ss a')
                                      .format(DateTime.parse(row['check_in_time'] as String).toLocal())
                                  : null;
                              final checkOut = row['check_out_time'] != null
                                  ? DateFormat('h:mm:ss a')
                                      .format(DateTime.parse(row['check_out_time'] as String).toLocal())
                                  : null;
                              final subtitle = [
                                if (checkIn != null) 'In: $checkIn',
                                if (checkOut != null) 'Out: $checkOut',
                              ].join(' · ');
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.check_circle, color: Colors.green),
                                  title: Text(name),
                                  subtitle: Text(subtitle.isEmpty ? '—' : subtitle),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
