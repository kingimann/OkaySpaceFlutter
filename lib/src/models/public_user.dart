import 'badge.dart';
import 'json.dart';

/// A public view of another user (profiles, conversation members, …).
///
/// Carries the commonly used fields; the complete payload is kept in [raw].
class PublicUser {
  const PublicUser({
    required this.userId,
    required this.name,
    this.username,
    this.picture,
    this.bio,
    this.headline,
    this.verified = false,
    this.online = false,
    this.role = 'user',
    this.badges = const [],
    this.isFollowing = false,
    this.isFollowedBy = false,
    this.friendStatus,
    this.subscriberCount = 0,
    this.subPrice = 0,
    this.points = 0,
    this.level = 0,
    this.raw = const {},
  });

  final String userId;
  final String name;
  final String? username;
  final String? picture;
  final String? bio;
  final String? headline;
  final bool verified;
  final bool online;
  final String role;
  final List<Badge> badges;
  final bool isFollowing;
  final bool isFollowedBy;
  final String? friendStatus;
  final int subscriberCount;
  final num subPrice;
  final int points;
  final int level;
  final Map<String, dynamic> raw;

  String get handle => username != null ? '@$username' : name;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        userId: asString(json['user_id'] ?? json['id']),
        name: asString(json['name']),
        username: asStringOrNull(json['username']),
        picture: asStringOrNull(json['picture']),
        bio: asStringOrNull(json['bio']),
        headline: asStringOrNull(json['headline']),
        verified: asBool(json['verified']),
        online: asBool(json['online']),
        role: asString(json['role'], 'user'),
        badges: asModelList(json['badges'], Badge.fromJson),
        isFollowing: asBool(json['is_following']),
        isFollowedBy: asBool(json['is_followed_by']),
        friendStatus: asStringOrNull(json['friend_status']),
        subscriberCount: asInt(json['subscriber_count']),
        subPrice: asDoubleOrNull(json['sub_price']) ?? 0,
        points: asInt(json['points']),
        level: asInt(json['level']),
        raw: json,
      );
}
