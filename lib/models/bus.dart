import 'package:equatable/equatable.dart';

class Bus extends Equatable {
  const Bus({
    required this.id,
    required this.busNumber,
    this.route,
    this.driverName,
    this.driverContact,
    this.capacity,
  });

  final String id;
  final String busNumber;
  final String? route;
  final String? driverName;
  final String? driverContact;
  final int? capacity;

  factory Bus.fromJson(Map<String, dynamic> json) => Bus(
        id: json['id'] as String,
        busNumber: json['bus_number'] as String,
        route: json['route'] as String?,
        driverName: json['driver_name'] as String?,
        driverContact: json['driver_contact'] as String?,
        capacity: json['capacity'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'bus_number': busNumber,
        'route': route,
        'driver_name': driverName,
        'driver_contact': driverContact,
        'capacity': capacity,
      };

  @override
  List<Object?> get props => [id, busNumber];
}
