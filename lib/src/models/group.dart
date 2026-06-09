import 'json.dart';

/// A group (Facebook-style membership community).
class Group {
  const Group({
    required this.id,
    required this.name,
    this.description,
    this.color = '',
    this.coverImage,
    this.isPrivate = false,
    this.rules = const [],
    required this.ownerId,
    this.memberCount = 0,
    this.isMember = false,
    this.membershipPending = false,
    this.myRole = 'none',
    this.pendingRequestCount = 0,
    this.pinnedPostIds = const [],
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String? description;
  final String color;
  final String? coverImage;
  final bool isPrivate;
  final List<String> rules;
  final String ownerId;
  final int memberCount;
  final bool isMember;
  final bool membershipPending;
  final String myRole;
  final int pendingRequestCount;
  final List<String> pinnedPostIds;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  bool get canManage => myRole == 'owner' || myRole == 'admin';

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: asString(json['id']),
        name: asString(json['name']),
        description: asStringOrNull(json['description']),
        color: asString(json['color']),
        coverImage: asStringOrNull(json['cover_image']),
        isPrivate: asBool(json['is_private']),
        rules: asStringList(json['rules']),
        ownerId: asString(json['owner_id']),
        memberCount: asInt(json['member_count']),
        isMember: asBool(json['is_member']),
        membershipPending: asBool(json['membership_pending']),
        myRole: asString(json['my_role'], 'none'),
        pendingRequestCount: asInt(json['pending_request_count']),
        pinnedPostIds: asStringList(json['pinned_post_ids']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}

/// An event scheduled within a group.
class GroupEvent {
  const GroupEvent({
    required this.id,
    required this.groupId,
    required this.creatorId,
    this.creatorName = '',
    required this.title,
    this.description = '',
    this.location,
    required this.startsAt,
    this.goingCount = 0,
    this.going = false,
    this.canManage = false,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String groupId;
  final String creatorId;
  final String creatorName;
  final String title;
  final String description;
  final String? location;
  final DateTime startsAt;
  final int goingCount;
  final bool going;
  final bool canManage;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory GroupEvent.fromJson(Map<String, dynamic> json) => GroupEvent(
        id: asString(json['id']),
        groupId: asString(json['group_id']),
        creatorId: asString(json['creator_id']),
        creatorName: asString(json['creator_name']),
        title: asString(json['title']),
        description: asString(json['description']),
        location: asStringOrNull(json['location']),
        startsAt: asDate(json['starts_at']),
        goingCount: asInt(json['going_count']),
        going: asBool(json['going']),
        canManage: asBool(json['can_manage']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}
