import 'package:equatable/equatable.dart';

enum CalendarEventType { holiday, event, exam, sportsDay, annualDay }

class CalendarEvent extends Equatable {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.eventType,
    required this.eventDate,
    this.endDate,
    this.description,
    this.createdBy,
  });

  final String id;
  final String title;
  final CalendarEventType eventType;
  final DateTime eventDate;
  final DateTime? endDate;
  final String? description;
  final String? createdBy;

  static CalendarEventType _typeFromJson(String value) {
    switch (value) {
      case 'sports_day':
        return CalendarEventType.sportsDay;
      case 'annual_day':
        return CalendarEventType.annualDay;
      case 'holiday':
        return CalendarEventType.holiday;
      case 'exam':
        return CalendarEventType.exam;
      default:
        return CalendarEventType.event;
    }
  }

  static String _typeToJson(CalendarEventType type) {
    switch (type) {
      case CalendarEventType.sportsDay:
        return 'sports_day';
      case CalendarEventType.annualDay:
        return 'annual_day';
      case CalendarEventType.holiday:
        return 'holiday';
      case CalendarEventType.exam:
        return 'exam';
      case CalendarEventType.event:
        return 'event';
    }
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        eventType: _typeFromJson(json['event_type'] as String),
        eventDate: DateTime.parse(json['event_date'] as String),
        endDate:
            json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
        description: json['description'] as String?,
        createdBy: json['created_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'event_type': _typeToJson(eventType),
        'event_date': eventDate.toIso8601String().substring(0, 10),
        'end_date': endDate?.toIso8601String().substring(0, 10),
        'description': description,
        'created_by': createdBy,
      };

  @override
  List<Object?> get props => [id, title, eventType, eventDate];
}
