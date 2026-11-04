import 'package:flutter/material.dart';

import 'package:school_management_app/config/supabase_config.dart';
import 'package:school_management_app/main.dart';
import 'package:school_management_app/models/bus.dart';
import 'package:school_management_app/models/bus_stop.dart';
import 'package:school_management_app/models/profile.dart';
import 'package:school_management_app/services/audit_service.dart';
import 'package:school_management_app/services/excel_export_service.dart';
import 'package:school_management_app/widgets/searchable_picker.dart';
import 'package:school_management_app/utils/error_messages.dart';

/// Module 13 of the client spec: Transport Management.
class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<Bus> _buses = [];
  List<Profile> _students = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        supabase.from('buses').select().order('bus_number'),
        supabase
            .from(SupabaseConfig.profilesTable)
            .select()
            .eq('role', 'student')
            .order('full_name'),
      ]);
      setState(() {
        _buses = (results[0] as List).map((e) => Bus.fromJson(e as Map<String, dynamic>)).toList();
        _students = (results[1] as List)
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Buses tab ────────────────────────────────────────────────────────────

  Future<void> _openBusDialog({Bus? existing}) async {
    final numberCtrl = TextEditingController(text: existing?.busNumber ?? '');
    final routeCtrl = TextEditingController(text: existing?.route ?? '');
    final driverCtrl = TextEditingController(text: existing?.driverName ?? '');
    final contactCtrl = TextEditingController(text: existing?.driverContact ?? '');
    final capacityCtrl =
        TextEditingController(text: existing?.capacity?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'New Bus' : 'Edit Bus'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: numberCtrl,
                  decoration: const InputDecoration(labelText: 'Bus number')),
              TextField(
                  controller: routeCtrl, decoration: const InputDecoration(labelText: 'Route')),
              TextField(
                  controller: driverCtrl,
                  decoration: const InputDecoration(labelText: 'Driver name')),
              TextField(
                  controller: contactCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Driver contact')),
              TextField(
                controller: capacityCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacity'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (numberCtrl.text.trim().isEmpty) return;
              try {
                final payload = {
                  'bus_number': numberCtrl.text.trim(),
                  'route': routeCtrl.text.trim().isEmpty ? null : routeCtrl.text.trim(),
                  'driver_name': driverCtrl.text.trim().isEmpty ? null : driverCtrl.text.trim(),
                  'driver_contact':
                      contactCtrl.text.trim().isEmpty ? null : contactCtrl.text.trim(),
                  'capacity':
                      capacityCtrl.text.trim().isEmpty ? null : int.tryParse(capacityCtrl.text.trim()),
                };
                if (existing == null) {
                  await supabase.from('buses').insert(payload);
                } else {
                  await supabase.from('buses').update(payload).eq('id', existing.id);
                }
                await AuditService.log(
                    module: 'transport', action: existing == null ? 'create_bus' : 'update_bus', newValue: payload);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _loadAll();
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildBusesTab() {
    return Scaffold(
      body: _buses.isEmpty
          ? const Center(child: Text('No buses yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _buses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final b = _buses[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_bus_filled_outlined),
                    title: Text('${b.busNumber}${b.route != null ? ' · ${b.route}' : ''}'),
                    subtitle: Text(
                        '${b.driverName ?? 'No driver assigned'} · ${b.driverContact ?? '—'}\nCapacity: ${b.capacity ?? '—'}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openBusDialog(existing: b),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_bus',
        onPressed: () => _openBusDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Bus'),
      ),
    );
  }

  // ── Stops tab ────────────────────────────────────────────────────────────

  Bus? _stopsBus;
  List<BusStop> _stops = [];

  Future<void> _loadStops(String busId) async {
    final data =
        await supabase.from('bus_stops').select().eq('bus_id', busId).order('sequence');
    setState(() {
      _stops = (data as List).map((e) => BusStop.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<void> _addStop() async {
    if (_stopsBus == null) return;
    final nameCtrl = TextEditingController();
    final seqCtrl = TextEditingController(text: (_stops.length + 1).toString());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Stop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Stop name')),
            TextField(
                controller: seqCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sequence')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await supabase.from('bus_stops').insert({
                  'bus_id': _stopsBus!.id,
                  'stop_name': nameCtrl.text.trim(),
                  'sequence': int.tryParse(seqCtrl.text.trim()) ?? 0,
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _loadStops(_stopsBus!.id);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildStopsTab() {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<Bus>(
              initialValue: _stopsBus,
              decoration: const InputDecoration(labelText: 'Select bus'),
              items: _buses.map((b) => DropdownMenuItem(value: b, child: Text(b.busNumber))).toList(),
              onChanged: (b) {
                setState(() => _stopsBus = b);
                if (b != null) _loadStops(b.id);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _stopsBus == null
                  ? const Center(child: Text('Pick a bus to view its stops'))
                  : _stops.isEmpty
                      ? const Center(child: Text('No stops yet'))
                      : ListView.separated(
                          itemCount: _stops.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final s = _stops[i];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Text('${s.sequence}')),
                                title: Text(s.stopName),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    await supabase.from('bus_stops').delete().eq('id', s.id);
                                    await _loadStops(_stopsBus!.id);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _stopsBus == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add_stop',
              onPressed: _addStop,
              icon: const Icon(Icons.add),
              label: const Text('Stop'),
            ),
    );
  }

  // ── Assign students tab ─────────────────────────────────────────────────

  List<Map<String, dynamic>> _assignments = [];

  Future<void> _loadAssignments() async {
    final data = await supabase
        .from('student_transport')
        .select('*, profiles(full_name), buses(bus_number), bus_stops(stop_name)');
    setState(() => _assignments = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _assignStudent() async {
    if (_buses.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add a bus first')));
      return;
    }
    Profile? selectedStudent;
    Bus selectedBus = _buses.first;
    List<BusStop> stopsForBus = [];
    BusStop? selectedStop;

    Future<void> refreshStops(void Function(void Function()) setDialogState) async {
      final data = await supabase
          .from('bus_stops')
          .select()
          .eq('bus_id', selectedBus.id)
          .order('sequence');
      setDialogState(() {
        stopsForBus =
            (data as List).map((e) => BusStop.fromJson(e as Map<String, dynamic>)).toList();
        selectedStop = stopsForBus.isNotEmpty ? stopsForBus.first : null;
      });
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          if (stopsForBus.isEmpty && selectedStop == null) {
            refreshStops(setDialogState);
          }
          return AlertDialog(
            title: const Text('Assign Student to Bus'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Student'),
                    subtitle: Text(selectedStudent?.fullName ?? 'Tap to select'),
                    trailing: const Icon(Icons.search),
                    onTap: () async {
                      final picked = await showDialog<Profile>(
                        context: context,
                        builder: (_) => Dialog(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SearchablePicker<Profile>(
                              items: _students,
                              labelOf: (s) => s.fullName,
                              subtitleOf: (s) => s.email,
                              onSelected: (s) => Navigator.pop(context, s),
                            ),
                          ),
                        ),
                      );
                      if (picked != null) setDialogState(() => selectedStudent = picked);
                    },
                  ),
                  DropdownButtonFormField<Bus>(
                    initialValue: selectedBus,
                    decoration: const InputDecoration(labelText: 'Bus'),
                    items:
                        _buses.map((b) => DropdownMenuItem(value: b, child: Text(b.busNumber))).toList(),
                    onChanged: (b) {
                      if (b == null) return;
                      setDialogState(() {
                        selectedBus = b;
                        stopsForBus = [];
                        selectedStop = null;
                      });
                      refreshStops(setDialogState);
                    },
                  ),
                  DropdownButtonFormField<BusStop>(
                    initialValue: selectedStop,
                    decoration: const InputDecoration(labelText: 'Pickup/drop stop'),
                    items: stopsForBus
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.stopName)))
                        .toList(),
                    onChanged: (s) => setDialogState(() => selectedStop = s),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (selectedStudent == null) return;
                  try {
                    await supabase.from('student_transport').upsert({
                      'student_id': selectedStudent!.id,
                      'bus_id': selectedBus.id,
                      'stop_id': selectedStop?.id,
                    });
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    await _loadAssignments();
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext)
                          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
                    }
                  }
                },
                child: const Text('Assign'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAssignTab() {
    if (_assignments.isEmpty) _loadAssignments();
    return Scaffold(
      body: _assignments.isEmpty
          ? const Center(child: Text('No students assigned yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _assignments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = _assignments[i];
                final name = (a['profiles'] as Map?)?['full_name'] as String? ?? '—';
                final busNumber = (a['buses'] as Map?)?['bus_number'] as String? ?? '—';
                final stopName = (a['bus_stops'] as Map?)?['stop_name'] as String?;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_pin_circle_outlined),
                    title: Text(name),
                    subtitle: Text('Bus $busNumber${stopName != null ? ' · $stopName' : ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        await supabase.from('student_transport').delete().eq('id', a['id'] as String);
                        await _loadAssignments();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'assign_student',
        onPressed: _assignStudent,
        icon: const Icon(Icons.add),
        label: const Text('Assign'),
      ),
    );
  }

  Future<void> _exportCurrentTab() async {
    try {
      switch (_tabController.index) {
        case 0:
          await ExcelExportService.exportRows(
            fileBaseName: 'buses',
            headers: const ['Bus Number', 'Route', 'Driver', 'Driver Contact', 'Capacity'],
            rows: _buses
                .map((b) => [
                      b.busNumber,
                      b.route ?? '',
                      b.driverName ?? '',
                      b.driverContact ?? '',
                      b.capacity?.toString() ?? '',
                    ])
                .toList(),
          );
          break;
        case 1:
          await ExcelExportService.exportRows(
            fileBaseName: 'bus_stops_${_stopsBus?.busNumber ?? ''}',
            headers: const ['Sequence', 'Stop Name'],
            rows: _stops.map((s) => [s.sequence, s.stopName]).toList(),
          );
          break;
        case 2:
          await ExcelExportService.exportRows(
            fileBaseName: 'student_transport_assignments',
            headers: const ['Student', 'Bus', 'Stop'],
            rows: _assignments
                .map((a) => [
                      (a['profiles'] as Map?)?['full_name'] as String? ?? '—',
                      (a['buses'] as Map?)?['bus_number'] as String? ?? '—',
                      (a['bus_stops'] as Map?)?['stop_name'] as String? ?? '',
                    ])
                .toList(),
          );
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  bool get _currentTabHasData {
    switch (_tabController.index) {
      case 0:
        return _buses.isNotEmpty;
      case 1:
        return _stops.isNotEmpty;
      case 2:
        return _assignments.isNotEmpty;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transport Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: 'Export current tab as Excel',
            onPressed: _currentTabHasData ? _exportCurrentTab : null,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [Tab(text: 'Buses'), Tab(text: 'Stops'), Tab(text: 'Assign')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildBusesTab(), _buildStopsTab(), _buildAssignTab()],
            ),
    );
  }
}
