import 'json.dart';
import 'post.dart';
import 'public_user.dart';

/// A message within a conversation. Messages are polymorphic (text, media,
/// voice, place, post, gif, file, contact, form, money, poll); the [type]
/// field selects which payload is populated, and [raw] always holds the rest.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.type = 'text',
    this.text,
    this.media = const [],
    this.audioBase64,
    this.audioDurationMs,
    this.transcript,
    this.postId,
    this.gifUrl,
    this.amount,
    this.pollQuestion,
    this.pollOptions = const [],
    this.replyToId,
    this.deleted = false,
    this.pinned = false,
    this.readBy = const [],
    this.deliveredBy = const [],
    this.editedAt,
    this.expiresAt,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String? text;
  final List<PostMedia> media;
  final String? audioBase64;
  final int? audioDurationMs;
  final String? transcript;
  final String? postId;
  final String? gifUrl;
  final num? amount;
  final String? pollQuestion;
  final List<String> pollOptions;
  final String? replyToId;
  final bool deleted;
  final bool pinned;
  final List<String> readBy;
  final List<String> deliveredBy;
  final DateTime? editedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: asString(json['id']),
        conversationId: asString(json['conversation_id']),
        senderId: asString(json['sender_id']),
        type: asString(json['type'], 'text'),
        text: asStringOrNull(json['text']),
        media: asModelList(json['media'], PostMedia.fromJson),
        audioBase64: asStringOrNull(json['audio_base64']),
        audioDurationMs: asIntOrNull(json['audio_duration_ms']),
        transcript: asStringOrNull(json['transcript']),
        postId: asStringOrNull(json['post_id']),
        gifUrl: asStringOrNull(json['gif_url']),
        amount: asDoubleOrNull(json['amount']),
        pollQuestion: asStringOrNull(json['poll_question']),
        pollOptions: asStringList(json['poll_options']),
        replyToId: asStringOrNull(json['reply_to_id']),
        deleted: asBool(json['deleted']),
        pinned: asBool(json['pinned']),
        readBy: asStringList(json['read_by']),
        deliveredBy: asStringList(json['delivered_by']),
        editedAt: asDateOrNull(json['edited_at']),
        expiresAt: asDateOrNull(json['expires_at']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}

/// A conversation (one-to-one or group) as returned by the messaging API.
class ConversationView {
  const ConversationView({
    required this.id,
    this.kind = 'direct',
    this.name,
    this.avatar,
    this.theme,
    this.disappearingSeconds = 0,
    this.receiptsEnabled = true,
    this.otherUser,
    this.members = const [],
    this.ownerId,
    this.listingId,
    this.listingTitle,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String kind; // 'direct' | 'group'
  final String? name;
  final String? avatar;
  final String? theme;
  final int disappearingSeconds;
  final bool receiptsEnabled;
  final PublicUser? otherUser;
  final List<PublicUser> members;
  final String? ownerId;
  final String? listingId;
  final String? listingTitle;
  final Message? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  bool get isGroup => kind == 'group';

  factory ConversationView.fromJson(Map<String, dynamic> json) {
    final other = asMapOrNull(json['other_user']);
    final last = asMapOrNull(json['last_message']);
    return ConversationView(
      id: asString(json['id']),
      kind: asString(json['kind'], 'direct'),
      name: asStringOrNull(json['name']),
      avatar: asStringOrNull(json['avatar']),
      theme: asStringOrNull(json['theme']),
      disappearingSeconds: asInt(json['disappearing_seconds']),
      receiptsEnabled: asBool(json['receipts_enabled'], true),
      otherUser: other != null ? PublicUser.fromJson(other) : null,
      members: asModelList(json['members'], PublicUser.fromJson),
      ownerId: asStringOrNull(json['owner_id']),
      listingId: asStringOrNull(json['listing_id']),
      listingTitle: asStringOrNull(json['listing_title']),
      lastMessage: last != null ? Message.fromJson(last) : null,
      lastMessageAt: asDateOrNull(json['last_message_at']),
      unreadCount: asInt(json['unread_count']),
      createdAt: asDate(json['created_at']),
      raw: json,
    );
  }
}

/// A snapshot of a live-location share: where the sharer is now, and whether
/// the share is still running.
class LiveLocationView {
  const LiveLocationView({
    required this.shareId,
    required this.userId,
    this.name,
    required this.latitude,
    required this.longitude,
    this.active = true,
    this.expiresAt,
    this.updatedAt,
  });

  final String shareId;
  final String userId;
  final String? name;
  final double latitude;
  final double longitude;
  final bool active;
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  factory LiveLocationView.fromJson(Map<String, dynamic> json) =>
      LiveLocationView(
        shareId: asString(json['share_id']),
        userId: asString(json['user_id']),
        name: asStringOrNull(json['name']),
        latitude: asDoubleOrNull(json['latitude']) ?? 0,
        longitude: asDoubleOrNull(json['longitude']) ?? 0,
        active: asBool(json['active'], true),
        expiresAt: asDateOrNull(json['expires_at']),
        updatedAt: asDateOrNull(json['updated_at']),
      );
}

/// Request body for sending a message. Defaults to a plain text message.
class MessageCreate {
  const MessageCreate({
    this.type = 'text',
    this.text,
    this.media = const [],
    this.audioBase64,
    this.audioDurationMs,
    this.postId,
    this.gifUrl,
    this.amount,
    this.pollQuestion,
    this.pollOptions,
    this.placeName,
    this.placeAddress,
    this.placeLongitude,
    this.placeLatitude,
    this.fileBase64,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.contactUserId,
    this.replyTo,
  });

  final String type;
  final String? text;
  final List<PostMedia> media;
  final String? audioBase64;
  final int? audioDurationMs;
  final String? postId;
  final String? gifUrl;
  final num? amount;
  final String? pollQuestion;
  final List<String>? pollOptions;
  final String? placeName;
  final String? placeAddress;
  final double? placeLongitude;
  final double? placeLatitude;
  final String? fileBase64;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;
  final String? contactUserId;
  final String? replyTo;

  /// A plain text message.
  factory MessageCreate.text(String text, {String? replyTo}) =>
      MessageCreate(type: 'text', text: text, replyTo: replyTo);

  Map<String, dynamic> toJson() => {
        'type': type,
        if (text != null) 'text': text,
        if (media.isNotEmpty) 'media': media.map((m) => m.toJson()).toList(),
        if (audioBase64 != null) 'audio_base64': audioBase64,
        if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
        if (postId != null) 'post_id': postId,
        if (gifUrl != null) 'gif_url': gifUrl,
        if (amount != null) 'amount': amount,
        if (pollQuestion != null) 'poll_question': pollQuestion,
        if (pollOptions != null) 'poll_options': pollOptions,
        if (placeName != null) 'place_name': placeName,
        if (placeAddress != null) 'place_address': placeAddress,
        if (placeLongitude != null) 'place_longitude': placeLongitude,
        if (placeLatitude != null) 'place_latitude': placeLatitude,
        if (fileBase64 != null) 'file_base64': fileBase64,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (fileMime != null) 'file_mime': fileMime,
        if (contactUserId != null) 'contact_user_id': contactUserId,
        if (replyTo != null) 'reply_to': replyTo,
      };
}
