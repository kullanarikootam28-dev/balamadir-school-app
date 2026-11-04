import 'package:equatable/equatable.dart';

class ExpenseCategory extends Equatable {
  const ExpenseCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) => ExpenseCategory(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  @override
  List<Object?> get props => [id, name];
}
