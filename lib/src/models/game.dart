import 'json.dart';

/// A playable game listing (Three.js bundle or hosted URL) with SDK
/// leaderboards. Mirrors the `/games` payload.
class Game {
  const Game({
    required this.id,
    required this.title,
    this.description,
    this.thumbnail,
    this.ownerId,
    this.ownerName,
    this.kind = 'url',
    this.plays = 0,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String title;
  final String? description;
  final String? thumbnail;
  final String? ownerId;
  final String? ownerName;

  /// 'url' (hosted) or 'bundle' (uploaded).
  final String kind;
  final int plays;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory Game.fromJson(Map<String, dynamic> json) => Game(
        id: asString(json['id'] ?? json['game_id']),
        title: asString(json['title'], 'Game'),
        description: asStringOrNull(json['description']),
        thumbnail: asStringOrNull(json['thumbnail'] ?? json['cover']),
        ownerId: asStringOrNull(json['owner_id']),
        ownerName: asStringOrNull(json['owner_name']),
        kind: asString(json['kind'], 'url'),
        plays: asInt(json['plays']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}
