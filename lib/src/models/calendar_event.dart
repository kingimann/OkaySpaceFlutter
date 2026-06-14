import 'json.dart';

/// A personal calendar event, private to its owner.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startAt,
    this.endAt,
    this.allDay = false,
    this.notes,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;
  final String? notes;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: asString(json['id']),
        title: asString(json['title']),
        startAt: asDate(json['start_at']),
        endAt: asDateOrNull(json['end_at']),
        allDay: asBool(json['all_day']),
        notes: asStringOrNull(json['notes']),
        color: asStringOrNull(json['color']),
        createdAt: asDate(json['created_at']),
        updatedAt: asDate(json['updated_at']),
      );
}
