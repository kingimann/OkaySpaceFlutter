import '../core/api_client.dart';
import '../models/group.dart';
import '../models/json.dart';
import '../models/post.dart';
import '../models/post_create.dart';

/// Endpoints under `/groups`: membership, posts, pins, events and requests.
class GroupsService {
  GroupsService(this._client);

  final ApiClient _client;

  Group _group(Object? d) => Group.fromJson(asMapOrNull(d) ?? const {});

  /// Groups the current user can see / is a member of.
  Future<List<Group>> list() async =>
      asModelList(await _client.getJson('/groups'), Group.fromJson);

  Future<Group> get(String groupId) async =>
      _group(await _client.getJson('/groups/$groupId'));

  Future<Group> create({
    required String name,
    String? description,
    String? color,
    bool? isPrivate,
  }) async =>
      _group(await _client.postJson('/groups', body: {
        'name': name,
        if (description != null) 'description': description,
        if (color != null) 'color': color,
        if (isPrivate != null) 'is_private': isPrivate,
      }));

  Future<Group> update(String groupId, Map<String, dynamic> changes) async =>
      _group(await _client.patchJson('/groups/$groupId', body: changes));

  Future<void> delete(String groupId) async {
    await _client.deleteJson('/groups/$groupId');
  }

  /// Joins a group (or requests to join, for private groups).
  Future<Group> join(String groupId) async =>
      _group(await _client.postJson('/groups/$groupId/join'));

  Future<Group> leave(String groupId) async =>
      _group(await _client.postJson('/groups/$groupId/leave'));

  Future<dynamic> members(String groupId) =>
      _client.getJson('/groups/$groupId/members');

  Future<Group> promoteMember(String groupId, String userId) async => _group(
      await _client.postJson('/groups/$groupId/members/$userId/promote'));

  Future<Group> demoteMember(String groupId, String userId) async =>
      _group(await _client.postJson('/groups/$groupId/members/$userId/demote'));

  Future<Group> removeMember(String groupId, String userId) async =>
      _group(await _client.deleteJson('/groups/$groupId/members/$userId'));

  // --- Posts & pins -------------------------------------------------------

  Future<List<Post>> posts(String groupId) async =>
      asModelList(await _client.getJson('/groups/$groupId/posts'), Post.fromJson);

  Future<Post> createPost(String groupId, PostCreate post) async => Post.fromJson(
      asMapOrNull(await _client.postJson('/groups/$groupId/posts',
              body: post.toJson())) ??
          const {});

  Future<List<Post>> pins(String groupId) async =>
      asModelList(await _client.getJson('/groups/$groupId/pins'), Post.fromJson);

  Future<Group> pinPost(String groupId, String postId) async =>
      _group(await _client.postJson('/groups/$groupId/pins/$postId'));

  Future<Group> unpinPost(String groupId, String postId) async =>
      _group(await _client.deleteJson('/groups/$groupId/pins/$postId'));

  // --- Join requests (private groups) -------------------------------------

  Future<dynamic> joinRequests(String groupId) =>
      _client.getJson('/groups/$groupId/requests');

  Future<Group> approveRequest(String groupId, String userId) async => _group(
      await _client.postJson('/groups/$groupId/requests/$userId/approve'));

  Future<Group> rejectRequest(String groupId, String userId) async => _group(
      await _client.postJson('/groups/$groupId/requests/$userId/reject'));

  // --- Events -------------------------------------------------------------

  Future<List<GroupEvent>> events(String groupId) async => asModelList(
      await _client.getJson('/groups/$groupId/events'), GroupEvent.fromJson);

  Future<GroupEvent> createEvent(
    String groupId, {
    required String title,
    required DateTime startsAt,
    String? description,
    String? location,
  }) async =>
      GroupEvent.fromJson(asMapOrNull(
              await _client.postJson('/groups/$groupId/events', body: {
            'title': title,
            'starts_at': startsAt.toUtc().toIso8601String(),
            if (description != null) 'description': description,
            if (location != null) 'location': location,
          })) ??
          const {});

  Future<void> deleteEvent(String groupId, String eventId) async {
    await _client.deleteJson('/groups/$groupId/events/$eventId');
  }

  /// Toggles RSVP for an event.
  Future<void> rsvpEvent(String groupId, String eventId) async {
    await _client.postJson('/groups/$groupId/events/$eventId/rsvp');
  }
}
