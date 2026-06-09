import 'json.dart';

/// A community (Reddit-style topic hub).
class Community {
  const Community({
    required this.id,
    required this.name,
    required this.title,
    this.description = '',
    this.color = '',
    this.icon = '',
    this.banner,
    this.rules = const [],
    this.flairs = const [],
    required this.ownerId,
    this.memberCount = 0,
    this.postCount = 0,
    this.isMember = false,
    this.isFavorite = false,
    this.role,
    this.canModerate = false,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String name; // slug, used in URLs
  final String title;
  final String description;
  final String color;
  final String icon;
  final String? banner;
  final List<String> rules;
  final List<String> flairs;
  final String ownerId;
  final int memberCount;
  final int postCount;
  final bool isMember;
  final bool isFavorite;
  final String? role;
  final bool canModerate;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory Community.fromJson(Map<String, dynamic> json) => Community(
        id: asString(json['id']),
        name: asString(json['name']),
        title: asString(json['title']),
        description: asString(json['description']),
        color: asString(json['color']),
        icon: asString(json['icon']),
        banner: asStringOrNull(json['banner']),
        rules: asStringList(json['rules']),
        flairs: asStringList(json['flairs']),
        ownerId: asString(json['owner_id']),
        memberCount: asInt(json['member_count']),
        postCount: asInt(json['post_count']),
        isMember: asBool(json['is_member']),
        isFavorite: asBool(json['is_favorite']),
        role: asStringOrNull(json['role']),
        canModerate: asBool(json['can_moderate']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}
