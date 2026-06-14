import 'json.dart';

/// A personal reminder / to-do, private to its owner.
class Reminder {
  const Reminder({
    required this.id,
    required this.text,
    this.dueAt,
    this.done = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String text;
  final DateTime? dueAt;
  final bool done;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: asString(json['id']),
        text: asString(json['text']),
        dueAt: asDateOrNull(json['due_at']),
        done: asBool(json['done']),
        createdAt: asDate(json['created_at']),
        updatedAt: asDate(json['updated_at']),
      );
}
