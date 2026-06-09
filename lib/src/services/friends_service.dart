import '../core/api_client.dart';
import '../models/json.dart';
import '../models/public_user.dart';

/// Endpoints under `/friends`: the friend list, incoming requests and the
/// request lifecycle (send / accept / reject / cancel / remove).
class FriendsService {
  FriendsService(this._client);

  final ApiClient _client;

  /// The current user's friends.
  Future<List<PublicUser>> friends() async =>
      asModelList(await _client.getJson('/friends'), PublicUser.fromJson);

  /// Incoming friend requests.
  Future<List<PublicUser>> requests() async => asModelList(
      await _client.getJson('/friends/requests'), PublicUser.fromJson);

  /// Sends a friend request to a user.
  Future<void> sendRequest(String userId) async {
    await _client.postJson('/friends/request/$userId');
  }

  /// Cancels a friend request you sent.
  Future<void> cancelRequest(String userId) async {
    await _client.deleteJson('/friends/request/$userId');
  }

  /// Accepts an incoming friend request.
  Future<void> accept(String userId) async {
    await _client.postJson('/friends/accept/$userId');
  }

  /// Rejects an incoming friend request.
  Future<void> reject(String userId) async {
    await _client.postJson('/friends/reject/$userId');
  }

  /// Removes an existing friend.
  Future<void> remove(String userId) async {
    await _client.deleteJson('/friends/$userId');
  }
}
