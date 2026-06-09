import 'json.dart';

/// An in-app notification (like, reply, follow, mention, message, …).
///
/// [type] selects which of the optional target ids (post/conversation/group)
/// is populated; [raw] retains the full payload.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    this.actorId,
    this.actorName,
    this.actorPicture,
    this.postId,
    this.conversationId,
    this.groupId,
    this.message,
    this.read = false,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String userId;
  final String type;
  final String? actorId;
  final String? actorName;
  final String? actorPicture;
  final String? postId;
  final String? conversationId;
  final String? groupId;
  final String? message;
  final bool read;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: asString(json['id']),
        userId: asString(json['user_id']),
        type: asString(json['type']),
        actorId: asStringOrNull(json['actor_id']),
        actorName: asStringOrNull(json['actor_name']),
        actorPicture: asStringOrNull(json['actor_picture']),
        postId: asStringOrNull(json['post_id']),
        conversationId: asStringOrNull(json['conversation_id']),
        groupId: asStringOrNull(json['group_id']),
        message: asStringOrNull(json['message']),
        read: asBool(json['read']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}
