import 'package:equatable/equatable.dart';

class BusStop extends Equatable {
  const BusStop({
    required this.id,
    required this.busId,
    required this.stopName,
    this.pickupTime,
    this.dropTime,
    this.sequence = 0,
  });

  final String id;
  final String busId;
  final String stopName;
  final String? pickupTime; // 'HH:mm:ss' as returned by Postgres time type
  final String? dropTime;
  final int sequence;

  factory BusStop.fromJson(Map<String, dynamic> json) => BusStop(
        id: json['id'] as String,
        busId: json['bus_id'] as String,
        stopName: json['stop_name'] as String,
        pickupTime: json['pickup_time'] as String?,
        dropTime: json['drop_time'] as String?,
        sequence: json['sequence'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'bus_id': busId,
        'stop_name': stopName,
        'pickup_time': pickupTime,
        'drop_time': dropTime,
        'sequence': sequence,
      };

  @override
  List<Object?> get props => [id, busId, stopName];
}
