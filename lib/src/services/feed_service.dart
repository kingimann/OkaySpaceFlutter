import '../core/api_client.dart';
import '../core/points_ledger.dart';
import '../models/json.dart';
import '../models/post.dart';
import '../models/post_create.dart';

/// Endpoints powering the social feed: feeds, posts, replies, and the common
/// engagement actions (like, repost, bookmark, vote).
class FeedService {
  FeedService(this._client);

  final ApiClient _client;

  List<Post> _posts(Object? data) => asModelList(data, Post.fromJson);
  Post _post(Object? data) => Post.fromJson(asMapOrNull(data) ?? const {});

  // --- Feeds --------------------------------------------------------------

  /// The personalized "Following / For You" home feed.
  Future<List<Post>> homeFeed({Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/feed/home', query: query));

  /// The discovery / explore feed.
  Future<List<Post>> exploreFeed({Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/feed/explore', query: query));

  /// The vertical-video reels feed.
  Future<List<Post>> reelsFeed({Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/feed/reels', query: query));

  /// Popular reels — a good fallback when the personalized reels feed is empty.
  Future<List<Post>> popularReels({int limit = 30}) async =>
      _posts(await _client.getJson('/reels/popular', query: {'limit': limit}));

  /// Resolves a stored/opaque video [url] into a directly-playable URL.
  /// Returns the original url if the backend gives nothing usable.
  Future<String> resolveVideoUrl(String url) async {
    try {
      final data =
          await _client.postJson('/media/resolve-video', body: {'url': url});
      final map = asMapOrNull(data);
      final resolved = map?['url'] ?? map?['resolved_url'] ?? map?['src'];
      if (resolved is String && resolved.isNotEmpty) return resolved;
    } catch (_) {
      // Fall through to the original URL.
    }
    return url;
  }

  /// Currently popular posts.
  Future<List<Post>> popularPosts({Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/posts/popular', query: query));

  /// Posts authored by [userId].
  Future<List<Post>> userPosts(String userId,
          {Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/posts/user/$userId', query: query));

  /// Posts tagged with a hashtag (without the leading `#`).
  Future<List<Post>> hashtagPosts(String tag,
          {Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/hashtags/$tag', query: query));

  /// The current user's bookmarked posts.
  Future<List<Post>> bookmarks() async =>
      _posts(await _client.getJson('/bookmarks'));

  /// Currently trending hashtags (raw payloads).
  Future<List<Map<String, dynamic>>> trendingHashtags() async {
    final data = await _client.getJson('/hashtags/trending');
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  // --- Single post --------------------------------------------------------

  /// Fetches a single post by id.
  Future<Post> getPost(String postId) async =>
      _post(await _client.getJson('/posts/$postId'));

  /// Lists replies to a post.
  Future<List<Post>> replies(String postId,
          {Map<String, dynamic>? query}) async =>
      _posts(await _client.getJson('/posts/$postId/replies', query: query));

  /// The full ancestor + descendant thread around a post.
  Future<List<Post>> thread(String postId) async =>
      _posts(await _client.getJson('/posts/$postId/thread'));

  // --- Authoring ----------------------------------------------------------

  /// Creates a post, reply (set [PostCreate.parentId]) or quote
  /// (set [PostCreate.quoteOf]).
  Future<Post> createPost(PostCreate post) async {
    final created = _post(await _client.postJson('/posts', body: post.toJson()));
    pointsLedger.award('posts', PointsLedger.postPoints);
    return created;
  }

  /// Convenience helper for a plain text post.
  Future<Post> post(String text) => createPost(PostCreate(text: text));

  /// Convenience helper to reply to [postId].
  Future<Post> reply(String postId, String text) =>
      createPost(PostCreate(text: text, parentId: postId));

  /// Edits a post's text/attachments. Pass only the fields to change.
  Future<Post> editPost(String postId, Map<String, dynamic> changes) async =>
      _post(await _client.patchJson('/posts/$postId', body: changes));

  /// Deletes a post.
  Future<void> deletePost(String postId) async {
    await _client.deleteJson('/posts/$postId');
  }

  // --- Engagement (each returns the updated post) -------------------------

  Future<Post> toggleLike(String postId) async {
    final updated = _post(await _client.postJson('/posts/$postId/like'));
    // Only reward adding a reaction, never removing one.
    if (updated.likedByMe) pointsLedger.award('reactions', PointsLedger.reactionPoints);
    return updated;
  }

  Future<Post> toggleDislike(String postId) async =>
      _post(await _client.postJson('/posts/$postId/dislike'));

  Future<Post> toggleRepost(String postId) async =>
      _post(await _client.postJson('/posts/$postId/repost'));

  Future<Post> toggleBookmark(String postId) async =>
      _post(await _client.postJson('/posts/$postId/bookmark'));

  Future<Post> togglePin(String postId) async =>
      _post(await _client.postJson('/posts/$postId/pin'));

  /// Adds/changes an emoji reaction on a post.
  Future<Post> react(String postId, String emoji) async =>
      _post(await _client.postJson('/posts/$postId/react', body: {'emoji': emoji}));

  /// Votes for [optionId] on a post's poll.
  Future<Post> votePoll(String postId, String optionId) async =>
      _post(await _client.postJson('/posts/$postId/vote',
          body: {'option_id': optionId}));

  /// Records a view (impression) for a post.
  Future<void> recordView(String postId) async {
    await _client.postJson('/posts/$postId/view');
  }

  /// Reports a post.
  Future<void> report(String postId, String reason) async {
    await _client.postJson('/posts/$postId/report', body: {'reason': reason});
  }

  /// Marks a post as "not interested" to tune recommendations.
  Future<void> notInterested(String postId) async {
    await _client.postJson('/posts/$postId/not-interested');
  }
}
