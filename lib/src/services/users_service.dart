import '../core/api_client.dart';
import '../core/points_ledger.dart';
import '../models/json.dart';
import '../models/post.dart';
import '../models/public_user.dart';

/// Endpoints under `/users`: public profiles, search, following, and creator
/// interactions (subscribe, tip, poke).
class UsersService {
  UsersService(this._client);

  final ApiClient _client;

  PublicUser _user(Object? d) => PublicUser.fromJson(asMapOrNull(d) ?? const {});

  /// A user's public profile.
  Future<PublicUser> publicProfile(String userId) async =>
      _user(await _client.getJson('/users/$userId/public'));

  /// Looks up a user by username (raw payload — may include extra fields).
  Future<Map<String, dynamic>> byUsername(String username) async =>
      asMapOrNull(await _client.getJson('/users/by-username/$username')) ??
      const {};

  /// Searches users.
  Future<List<PublicUser>> search(String query) async => asModelList(
      await _client.getJson('/users/search', query: {'q': query}),
      PublicUser.fromJson);

  /// Followers / following lists.
  Future<List<PublicUser>> followers(String userId) async => asModelList(
      await _client.getJson('/users/$userId/followers'), PublicUser.fromJson);

  Future<List<PublicUser>> following(String userId) async => asModelList(
      await _client.getJson('/users/$userId/following'), PublicUser.fromJson);

  // --- Interactions -------------------------------------------------------

  /// The global activity-points leaderboard (raw payloads).
  Future<List<Map<String, dynamic>>> leaderboard() async {
    final data = await _client.getJson('/points/leaderboard');
    final list = data is Map
        ? (data['leaders'] ??
            data['leaderboard'] ??
            data['users'] ??
            data['items'] ??
            data['data'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Toggles following a user.
  Future<void> follow(String userId) async {
    await _client.postJson('/users/$userId/follow');
    pointsLedger.award('social', PointsLedger.socialPoints);
  }

  /// Pokes a user.
  Future<void> poke(String userId) async {
    await _client.postJson('/users/$userId/poke');
  }

  /// Subscribes to a creator, optionally on a named [tier].
  Future<void> subscribe(String userId, {String? tier}) async {
    await _client.postJson('/users/$userId/subscribe',
        body: {if (tier != null) 'tier': tier});
  }

  Future<void> unsubscribe(String userId) async {
    await _client.deleteJson('/users/$userId/subscribe');
  }

  /// Tips a user. Returns the raw tip record.
  Future<Map<String, dynamic>> tip(String userId, num amount,
      {String? message}) async {
    final data = await _client.postJson('/users/$userId/tip', body: {
      'amount': amount,
      if (message != null) 'message': message,
    });
    return asMapOrNull(data) ?? const {};
  }

  /// Records a profile view.
  Future<void> recordView(String userId) async {
    await _client.postJson('/users/$userId/view');
  }

  /// Posts authored by a user (delegates to the posts endpoint).
  Future<List<Post>> posts(String userId) async => asModelList(
      await _client.getJson('/posts/user/$userId'), Post.fromJson);

  /// Posts a user has liked.
  Future<List<Post>> likes(String userId) async => asModelList(
      await _client.getJson('/posts/user/$userId/likes'), Post.fromJson);

  /// A user's replies.
  Future<List<Post>> replies(String userId) async => asModelList(
      await _client.getJson('/posts/user/$userId/replies'), Post.fromJson);

  /// A user's reposts.
  Future<List<Post>> reposts(String userId) async => asModelList(
      await _client.getJson('/posts/user/$userId/reposts'), Post.fromJson);
}
