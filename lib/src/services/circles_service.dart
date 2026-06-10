import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/circles`: audience circles — private groupings of people
/// a post can be limited to (via `PostCreate.audienceCircleId`).
class CirclesService {
  CirclesService(this._client);

  final ApiClient _client;

  List<Map<String, dynamic>> _list(dynamic data, [String? key]) {
    final list = data is Map
        ? (data[key] ?? data['circles'] ?? data['items'] ?? data['data'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// The current user's audience circles.
  Future<List<Map<String, dynamic>>> circles() async =>
      _list(await _client.getJson('/circles'));

  /// Members of a circle (raw payloads).
  Future<List<Map<String, dynamic>>> members(String circleId) async =>
      _list(await _client.getJson('/circles/$circleId/members'), 'members');

  Future<Map<String, dynamic>> create({
    required String name,
    List<String> memberIds = const [],
  }) async =>
      asMapOrNull(await _client.postJson('/circles',
          body: {'name': name, 'member_ids': memberIds})) ??
      const {};

  Future<Map<String, dynamic>> update(
    String circleId, {
    String? name,
    List<String> addMemberIds = const [],
    List<String> removeMemberIds = const [],
  }) async =>
      asMapOrNull(await _client.patchJson('/circles/$circleId', body: {
        if (name != null) 'name': name,
        if (addMemberIds.isNotEmpty) 'add_member_ids': addMemberIds,
        if (removeMemberIds.isNotEmpty) 'remove_member_ids': removeMemberIds,
      })) ??
      const {};

  Future<void> delete(String circleId) async {
    await _client.deleteJson('/circles/$circleId');
  }
}
