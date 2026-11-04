import 'package:equatable/equatable.dart';

class FeeType extends Equatable {
  const FeeType({required this.id, required this.name});

  final String id;
  final String name;

  factory FeeType.fromJson(Map<String, dynamic> json) => FeeType(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  Map<String, dynamic> toJson() => {'name': name};

  @override
  List<Object?> get props => [id, name];
}
