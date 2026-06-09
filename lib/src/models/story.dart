import 'json.dart';

/// A single story (image or video) authored by a user.
class Story {
  const Story({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPicture,
    this.userUsername,
    this.type = 'image',
    this.mediaBase64 = '',
    this.caption,
    this.durationMs,
    this.viewCount = 0,
    this.viewedByMe = false,
    required this.createdAt,
    required this.expiresAt,
    this.raw = const {},
  });

  final String id;
  final String userId;
  final String userName;
  final String? userPicture;
  final String? userUsername;
  final String type; // 'image' | 'video'
  final String mediaBase64;
  final String? caption;
  final int? durationMs;
  final int viewCount;
  final bool viewedByMe;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, dynamic> raw;

  bool get isVideo => type == 'video';
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory Story.fromJson(Map<String, dynamic> json) => Story(
        id: asString(json['id']),
        userId: asString(json['user_id']),
        userName: asString(json['user_name']),
        userPicture: asStringOrNull(json['user_picture']),
        userUsername: asStringOrNull(json['user_username']),
        type: asString(json['type'], 'image'),
        mediaBase64: asString(json['media_base64']),
        caption: asStringOrNull(json['caption']),
        durationMs: asIntOrNull(json['duration_ms']),
        viewCount: asInt(json['view_count']),
        viewedByMe: asBool(json['viewed_by_me']),
        createdAt: asDate(json['created_at']),
        expiresAt: asDate(json['expires_at']),
        raw: json,
      );
}

/// An entry in the stories tray (one per user with active stories).
class StoryTrayItem {
  const StoryTrayItem({
    required this.userId,
    required this.userName,
    this.userPicture,
    this.userUsername,
    this.hasUnviewed = false,
    this.storyCount = 0,
    required this.latestAt,
  });

  final String userId;
  final String userName;
  final String? userPicture;
  final String? userUsername;
  final bool hasUnviewed;
  final int storyCount;
  final DateTime latestAt;

  factory StoryTrayItem.fromJson(Map<String, dynamic> json) => StoryTrayItem(
        userId: asString(json['user_id']),
        userName: asString(json['user_name']),
        userPicture: asStringOrNull(json['user_picture']),
        userUsername: asStringOrNull(json['user_username']),
        hasUnviewed: asBool(json['has_unviewed']),
        storyCount: asInt(json['story_count']),
        latestAt: asDate(json['latest_at']),
      );
}

/// A viewer of a story.
class StoryViewer {
  const StoryViewer({
    required this.userId,
    required this.name,
    this.username,
    this.picture,
    required this.viewedAt,
  });

  final String userId;
  final String name;
  final String? username;
  final String? picture;
  final DateTime viewedAt;

  factory StoryViewer.fromJson(Map<String, dynamic> json) => StoryViewer(
        userId: asString(json['user_id']),
        name: asString(json['name']),
        username: asStringOrNull(json['username']),
        picture: asStringOrNull(json['picture']),
        viewedAt: asDate(json['viewed_at']),
      );
}

/// Media payload for creating a story.
class StoryMedia {
  const StoryMedia({required this.base64, this.type = 'image', this.durationMs});

  final String base64;
  final String type; // 'image' | 'video'
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        'type': type,
        'base64': base64,
        if (durationMs != null) 'duration_ms': durationMs,
      };
}
