import 'post.dart';

/// One option when creating a poll.
class PollOptionCreate {
  const PollOptionCreate(this.text);
  final String text;
  Map<String, dynamic> toJson() => {'text': text};
}

/// Poll payload for [PostCreate].
class PollCreate {
  const PollCreate({required this.options, required this.endsAt});

  final List<PollOptionCreate> options;
  final DateTime endsAt;

  Map<String, dynamic> toJson() => {
        'options': options.map((o) => o.toJson()).toList(),
        'ends_at': endsAt.toUtc().toIso8601String(),
      };
}

/// Request body for `POST /posts` (create a post, reply or quote).
class PostCreate {
  const PostCreate({
    this.text = '',
    this.parentId,
    this.quoteOf,
    this.media = const [],
    this.poll,
    this.taggedUserIds = const [],
    this.communityId,
    this.title,
    this.flair,
    this.likesDisabled,
    this.commentPolicy,
    this.minSubTier,
    this.audienceCircleId,
    this.placeName,
    this.placeLongitude,
    this.placeLatitude,
  });

  final String text;

  /// Set to reply to a post.
  final String? parentId;

  /// Set to quote-post another post.
  final String? quoteOf;

  final List<PostMedia> media;
  final PollCreate? poll;
  final List<String> taggedUserIds;
  final String? communityId;
  final String? title;
  final String? flair;
  final bool? likesDisabled;
  final String? commentPolicy;
  final int? minSubTier;
  final String? audienceCircleId;
  final String? placeName;
  final double? placeLongitude;
  final double? placeLatitude;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (parentId != null) 'parent_id': parentId,
        if (quoteOf != null) 'quote_of': quoteOf,
        if (media.isNotEmpty) 'media': media.map((m) => m.toJson()).toList(),
        if (poll != null) 'poll': poll!.toJson(),
        if (taggedUserIds.isNotEmpty) 'tagged_user_ids': taggedUserIds,
        if (communityId != null) 'community_id': communityId,
        if (title != null) 'title': title,
        if (flair != null) 'flair': flair,
        if (likesDisabled != null) 'likes_disabled': likesDisabled,
        if (commentPolicy != null) 'comment_policy': commentPolicy,
        if (minSubTier != null) 'min_sub_tier': minSubTier,
        if (audienceCircleId != null) 'audience_circle_id': audienceCircleId,
        if (placeName != null) 'place_name': placeName,
        if (placeLongitude != null) 'place_longitude': placeLongitude,
        if (placeLatitude != null) 'place_latitude': placeLatitude,
      };
}
