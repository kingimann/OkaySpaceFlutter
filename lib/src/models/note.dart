import 'json.dart';

/// A personal note (title + body), private to its owner.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.color,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? color;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: asString(json['id']),
        title: asString(json['title']),
        body: asString(json['body']),
        color: asStringOrNull(json['color']),
        pinned: asBool(json['pinned']),
        createdAt: asDate(json['created_at']),
        updatedAt: asDate(json['updated_at']),
      );
}
