import 'badge.dart';
import 'json.dart';

/// Compact author block embedded in every [Post].
class PostAuthor {
  const PostAuthor({
    required this.userId,
    required this.name,
    this.username,
    this.picture,
    this.verified = false,
    this.idVerified = false,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.badges = const [],
  });

  final String userId;
  final String name;
  final String? username;
  final String? picture;
  final bool verified;
  final bool idVerified;
  final bool phoneVerified;
  final bool emailVerified;
  final List<UserBadge> badges;

  factory PostAuthor.fromJson(Map<String, dynamic> json) => PostAuthor(
        userId: asString(json['user_id']),
        name: asString(json['name']),
        username: asStringOrNull(json['username']),
        picture: asStringOrNull(json['picture']),
        verified: asBool(json['verified']),
        idVerified: asBool(json['id_verified']),
        phoneVerified: asBool(json['phone_verified']),
        emailVerified: asBool(json['email_verified']),
        badges: asModelList(json['badges'], UserBadge.fromJson),
      );
}

/// An image or video attached to a post.
class PostMedia {
  const PostMedia({
    this.type = 'image',
    this.url,
    this.thumbnail,
    this.base64,
    this.width,
    this.height,
    this.duration,
  });

  final String type; // 'image' | 'video'
  final String? url;
  final String? thumbnail;

  /// Used only when *uploading* inline media; null on fetched posts.
  final String? base64;
  final int? width;
  final int? height;

  /// Video length in seconds (null for images / when unknown).
  final double? duration;

  bool get isVideo => type == 'video';

  /// Duration as m:ss for a badge, or null when unknown.
  String? get durationLabel {
    final d = duration;
    if (d == null || d <= 0) return null;
    final total = d.round();
    final m = total ~/ 60, s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  factory PostMedia.fromJson(Map<String, dynamic> json) => PostMedia(
        type: asString(json['type'], 'image'),
        url: asStringOrNull(json['url']),
        thumbnail: asStringOrNull(json['thumbnail']),
        base64: asStringOrNull(json['base64']),
        width: asIntOrNull(json['width']),
        height: asIntOrNull(json['height']),
        duration: asDoubleOrNull(json['duration']),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (base64 != null && base64!.isNotEmpty) 'base64': base64,
        if (url != null) 'url': url,
        if (thumbnail != null) 'thumbnail': thumbnail,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (duration != null) 'duration': duration,
      };
}

/// A user tagged in a post.
class TaggedUser {
  const TaggedUser({
    required this.userId,
    required this.name,
    this.username,
    this.picture,
  });

  final String userId;
  final String name;
  final String? username;
  final String? picture;

  factory TaggedUser.fromJson(Map<String, dynamic> json) => TaggedUser(
        userId: asString(json['user_id']),
        name: asString(json['name']),
        username: asStringOrNull(json['username']),
        picture: asStringOrNull(json['picture']),
      );
}

/// One choice within a [Poll].
class PollOption {
  const PollOption({required this.id, required this.text, this.votes = 0});

  final String id;
  final String text;
  final int votes;

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
        id: asString(json['id']),
        text: asString(json['text']),
        votes: asInt(json['votes']),
      );
}

/// An attached poll.
class Poll {
  const Poll({
    required this.options,
    this.totalVotes = 0,
    this.votedOptionId,
    this.endsAt,
    this.closed = false,
  });

  final List<PollOption> options;
  final int totalVotes;
  final String? votedOptionId;
  final DateTime? endsAt;
  final bool closed;

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
        options: asModelList(json['options'], PollOption.fromJson),
        totalVotes: asInt(json['total_votes']),
        votedOptionId: asStringOrNull(json['voted_option_id']),
        endsAt: asDateOrNull(json['ends_at']),
        closed: asBool(json['closed']),
      );
}

/// Unfurled link preview.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.siteName,
  });

  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
        url: asString(json['url']),
        title: asStringOrNull(json['title']),
        description: asStringOrNull(json['description']),
        image: asStringOrNull(json['image']),
        siteName: asStringOrNull(json['site_name']),
      );
}

/// Aggregate count for a single emoji reaction.
class ReactionCount {
  const ReactionCount({required this.emoji, this.count = 0});

  final String emoji;
  final int count;

  factory ReactionCount.fromJson(Map<String, dynamic> json) => ReactionCount(
        emoji: asString(json['emoji']),
        count: asInt(json['count']),
      );
}

/// A post in the social feed.
///
/// Posts are recursive — a repost or quote embeds the original via
/// [repostedPost] / [quotedPost].
class Post {
  const Post({
    required this.id,
    required this.userId,
    required this.author,
    required this.text,
    this.parentId,
    this.repostOf,
    this.quoteOf,
    this.repostedPost,
    this.quotedPost,
    this.media = const [],
    this.taggedUsers = const [],
    this.linkPreview,
    this.poll,
    this.hashtags = const [],
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.reactions = const [],
    this.reactionsTotal = 0,
    this.myReaction,
    this.repliesCount = 0,
    this.threadCount = 0,
    this.repostsCount = 0,
    this.quotesCount = 0,
    this.bookmarksCount = 0,
    this.viewsCount = 0,
    this.likedByMe = false,
    this.dislikedByMe = false,
    this.bookmarkedByMe = false,
    this.repostedByMe = false,
    this.pinned = false,
    this.promoted = false,
    this.locked = false,
    this.canComment = true,
    this.commentPolicy = 'everyone',
    this.communityId,
    this.communityName,
    this.title,
    this.flair,
    this.placeName,
    this.editedAt,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String userId;
  final PostAuthor author;
  final String text;

  final String? parentId;
  final String? repostOf;
  final String? quoteOf;
  final Post? repostedPost;
  final Post? quotedPost;

  final List<PostMedia> media;
  final List<TaggedUser> taggedUsers;
  final LinkPreview? linkPreview;
  final Poll? poll;
  final List<String> hashtags;

  final int likesCount;
  final int dislikesCount;
  final List<ReactionCount> reactions;
  final int reactionsTotal;
  final String? myReaction;
  final int repliesCount;

  /// Self-replies the author posted under this one — when > 0 the post is the
  /// head of a thread the author continued.
  final int threadCount;
  final int repostsCount;
  final int quotesCount;
  final int bookmarksCount;
  final int viewsCount;

  final bool likedByMe;
  final bool dislikedByMe;
  final bool bookmarkedByMe;
  final bool repostedByMe;
  final bool pinned;
  final bool promoted;
  final bool locked;
  final bool canComment;
  final String commentPolicy;

  final String? communityId;
  final String? communityName;
  final String? title;
  final String? flair;
  final String? placeName;

  final DateTime? editedAt;
  final DateTime createdAt;

  /// Full payload for any field not modelled explicitly.
  final Map<String, dynamic> raw;

  bool get isRepost => repostOf != null;
  bool get isQuote => quoteOf != null;
  bool get isReply => parentId != null;
  bool get isThread => threadCount > 0;

  factory Post.fromJson(Map<String, dynamic> json) {
    final reposted = asMapOrNull(json['reposted_post']);
    final quoted = asMapOrNull(json['quoted_post']);
    final preview = asMapOrNull(json['link_preview']);
    final poll = asMapOrNull(json['poll']);
    return Post(
      id: asString(json['id']),
      userId: asString(json['user_id']),
      author: PostAuthor.fromJson(asMapOrNull(json['author']) ?? const {}),
      text: asString(json['text']),
      parentId: asStringOrNull(json['parent_id']),
      repostOf: asStringOrNull(json['repost_of']),
      quoteOf: asStringOrNull(json['quote_of']),
      repostedPost: reposted != null ? Post.fromJson(reposted) : null,
      quotedPost: quoted != null ? Post.fromJson(quoted) : null,
      media: asModelList(json['media'], PostMedia.fromJson),
      taggedUsers: asModelList(json['tagged_users'], TaggedUser.fromJson),
      linkPreview: preview != null ? LinkPreview.fromJson(preview) : null,
      poll: poll != null ? Poll.fromJson(poll) : null,
      hashtags: asStringList(json['hashtags']),
      likesCount: asInt(json['likes_count']),
      dislikesCount: asInt(json['dislikes_count']),
      reactions: asModelList(json['reactions'], ReactionCount.fromJson),
      reactionsTotal: asInt(json['reactions_total']),
      myReaction: asStringOrNull(json['my_reaction']),
      repliesCount: asInt(json['replies_count']),
      threadCount: asInt(json['thread_count']),
      repostsCount: asInt(json['reposts_count']),
      quotesCount: asInt(json['quotes_count']),
      bookmarksCount: asInt(json['bookmarks_count']),
      viewsCount: asInt(json['views_count']),
      likedByMe: asBool(json['liked_by_me']),
      dislikedByMe: asBool(json['disliked_by_me']),
      bookmarkedByMe: asBool(json['bookmarked_by_me']),
      repostedByMe: asBool(json['reposted_by_me']),
      pinned: asBool(json['pinned']),
      promoted: asBool(json['promoted']),
      locked: asBool(json['locked']),
      canComment: asBool(json['can_comment'], true),
      commentPolicy: asString(json['comment_policy'], 'everyone'),
      communityId: asStringOrNull(json['community_id']),
      communityName: asStringOrNull(json['community_name']),
      title: asStringOrNull(json['title']),
      flair: asStringOrNull(json['flair']),
      placeName: asStringOrNull(json['place_name']),
      editedAt: asDateOrNull(json['edited_at']),
      createdAt: asDate(json['created_at']),
      raw: json,
    );
  }

  @override
  String toString() => 'Post($id by ${author.handle ?? author.userId})';
}

extension on PostAuthor {
  String? get handle => username != null ? '@$username' : null;
}
