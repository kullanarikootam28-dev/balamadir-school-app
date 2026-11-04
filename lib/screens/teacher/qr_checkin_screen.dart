import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:school_management_app/main.dart';

/// Teacher-side half of module 3: scans the admin's rotating QR code, then
/// shows an explicit In/Out choice (per client feedback, Bug3.pdf — the
/// teacher picks which one, the app doesn't guess from scan count) before
/// calling mark_attendance_via_qr (024_qr_explicit_inout.sql) for the
/// actual server-side verification. This screen only reports whatever the
/// function decides — it never marks attendance itself.
class QrCheckinScreen extends StatefulWidget {
  const QrCheckinScreen({super.key});

  @override
  State<QrCheckinScreen> createState() => _QrCheckinScreenState();
}

enum _ScanState { scanning, success, invalid, expired, error }

class _QrCheckinScreenState extends State<QrCheckinScreen> {
  final MobileScannerController _controller = MobileScannerController();
  _ScanState _state = _ScanState.scanning;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final token = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (token == null) return;

    setState(() => _busy = true);

    await _showInOutChoice(token);

    // Brief cooldown so the same frame doesn't immediately re-trigger.
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _busy = false);
  }

  /// The page the client asked for: after a scan, show In/Out as two clear
  /// options and let the teacher pick — nothing is recorded until they do.
  Future<void> _showInOutChoice(String token) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark Attendance'),
        content: const Text('Select whether this scan is your check-in or check-out.'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  icon: const Icon(Icons.login),
                  label: const Text('Check IN'),
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _submit(token, 'check_in');
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                  icon: const Icon(Icons.logout),
                  label: const Text('Check OUT'),
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _submit(token, 'check_out');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit(String token, String action) async {
    try {
      final result = await supabase.rpc('mark_attendance_via_qr', params: {
        'p_token': token,
        'p_action': action,
      });
      final success = result['success'] == true;
      final reason = result['reason'] as String?;
      setState(() {
        if (success) {
          _state = _ScanState.success;
        } else if (reason == 'expired') {
          _state = _ScanState.expired;
        } else {
          _state = _ScanState.invalid;
        }
      });
      if (success && mounted) {
        await _showResultDialog(action, result['time'] as String?);
      }
    } catch (e) {
      if (mounted) setState(() => _state = _ScanState.error);
    }
  }

  Future<void> _showResultDialog(String action, String? isoTime) async {
    final time = isoTime != null ? DateFormat('h:mm a').format(DateTime.parse(isoTime).toLocal()) : null;
    final (icon, color, message) = action == 'check_in'
        ? (Icons.login, Colors.green, 'Checked IN${time != null ? ' at $time' : ''}!')
        : (Icons.logout, Colors.blue, 'Checked OUT${time != null ? ' at $time' : ''}!');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, color: color, size: 40),
        title: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK')),
        ],
      ),
    );
  }

  void _reset() => setState(() => _state = _ScanState.scanning);

  (Color, IconData, String) get _banner {
    switch (_state) {
      case _ScanState.success:
        return (Colors.green, Icons.check_circle, 'Attendance marked!');
      case _ScanState.expired:
        return (Colors.orange, Icons.timer_off, 'That code expired. Ask the office to show the current one.');
      case _ScanState.invalid:
        return (Colors.red, Icons.error_outline, 'Invalid code. Try scanning again.');
      case _ScanState.error:
        return (Colors.red, Icons.wifi_off, 'Could not reach the server. Check your connection and try again.');
      case _ScanState.scanning:
        return (Colors.blue, Icons.qr_code_scanner, 'Point your camera at the attendance QR code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = _banner;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Attendance QR')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: color.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(icon, color: color, size: 40),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: color)),
                if (_state != _ScanState.scanning) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: _reset, child: const Text('Scan again')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
