import '../core/api_client.dart';
import '../models/community.dart';
import '../models/json.dart';
import '../models/post.dart';

/// Endpoints under `/communities`: discovery, membership, posts and
/// moderation.
class CommunitiesService {
  CommunitiesService(this._client);

  final ApiClient _client;

  Community _community(Object? d) =>
      Community.fromJson(asMapOrNull(d) ?? const {});

  /// Searches/browses communities.
  Future<List<Community>> list({String? query, String? sort}) async =>
      asModelList(
          await _client.getJson('/communities',
              query: {'q': query, 'sort': sort}),
          Community.fromJson);

  /// An aggregated feed of posts across the user's communities.
  Future<List<Post>> feed() async =>
      asModelList(await _client.getJson('/communities/feed'), Post.fromJson);

  /// Fetches a community by its [name] (slug).
  Future<Community> get(String name) async =>
      _community(await _client.getJson('/communities/$name'));

  /// Creates a community.
  Future<Community> create({
    required String name,
    String? title,
    String? description,
    String? color,
    String? icon,
    List<String>? rules,
    List<String>? flairs,
  }) async =>
      _community(await _client.postJson('/communities', body: {
        'name': name,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (rules != null) 'rules': rules,
        if (flairs != null) 'flairs': flairs,
      }));

  /// Updates a community (moderators only). Pass only fields to change.
  Future<Community> update(String name, Map<String, dynamic> changes) async =>
      _community(await _client.patchJson('/communities/$name', body: changes));

  Future<void> join(String name) async {
    await _client.postJson('/communities/$name/join');
  }

  Future<void> leave(String name) async {
    await _client.deleteJson('/communities/$name/join');
  }

  Future<void> favorite(String name) async {
    await _client.postJson('/communities/$name/favorite');
  }

  Future<void> unfavorite(String name) async {
    await _client.deleteJson('/communities/$name/favorite');
  }

  /// Posts in a community, with optional sort/flair/search filters.
  Future<List<Post>> posts(
    String name, {
    String? sort,
    String? flair,
    String? search,
  }) async =>
      asModelList(
        await _client.getJson('/communities/$name/posts',
            query: {'sort': sort, 'flair': flair, 'search': search}),
        Post.fromJson,
      );

  /// Per-community karma leaderboard (raw payloads, highest first).
  Future<List<Map<String, dynamic>>> topMembers(String name) async {
    final data = await _client.getJson('/communities/$name/top');
    final list = data is Map
        ? (data['top'] ?? data['members'] ?? data['leaderboard'] ?? data['items'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Members of a community (raw payload).
  Future<dynamic> members(String name) =>
      _client.getJson('/communities/$name/members');

  // Moderation
  Future<void> addModerator(String name, String userId) async {
    await _client.postJson('/communities/$name/mods/$userId');
  }

  Future<void> removeModerator(String name, String userId) async {
    await _client.deleteJson('/communities/$name/mods/$userId');
  }

  Future<void> removeMember(String name, String userId) async {
    await _client.deleteJson('/communities/$name/members/$userId');
  }

  Future<void> pinPost(String name, String postId) async {
    await _client.postJson('/communities/$name/posts/$postId/pin');
  }

  Future<void> removePost(String name, String postId) async {
    await _client.postJson('/communities/$name/posts/$postId/remove');
  }
}
