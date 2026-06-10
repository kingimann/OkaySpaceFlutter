import '../core/api_client.dart';
import '../models/game.dart';
import '../models/json.dart';

/// Endpoints under `/games`: browse/create games and SDK leaderboards.
class GamesService {
  GamesService(this._client);

  final ApiClient _client;

  List<T> _list<T>(Object? data, String key, T Function(Map<String, dynamic>) f) {
    final v = data is Map ? data[key] : data;
    return asModelList(v, f);
  }

  /// All published games.
  Future<List<Game>> games() async =>
      _list(await _client.getJson('/games'), 'games', Game.fromJson);

  Future<Game> game(String gameId) async =>
      Game.fromJson(asMapOrNull(await _client.getJson('/games/$gameId')) ?? const {});

  /// Creates a game (hosted `url` kind, or a Three.js bundle).
  Future<Game> create({
    required String title,
    String? description,
    String? url,
    String? thumbnail,
    String kind = 'url',
  }) async =>
      Game.fromJson(asMapOrNull(await _client.postJson('/games', body: {
            'title': title,
            'kind': kind,
            if (description != null) 'description': description,
            if (url != null) 'url': url,
            if (thumbnail != null) 'thumbnail': thumbnail,
          })) ??
          const {});

  Future<void> delete(String gameId) async {
    await _client.deleteJson('/games/$gameId');
  }

  /// Top scores for a game (defensive: returns raw entry maps).
  Future<List<Map<String, dynamic>>> leaderboard(String gameId) async {
    final data = await _client.getJson('/games/$gameId/leaderboard');
    final v = data is Map ? (data['leaderboard'] ?? data['entries']) : data;
    return v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  /// Records a play (bumps the play count).
  Future<void> recordPlay(String gameId) async {
    await _client.postJson('/games/$gameId/play', body: const {});
  }

  /// Submits a score to the leaderboard.
  Future<void> submitScore(String gameId, num score) async {
    await _client.postJson('/games/$gameId/score', body: {'score': score});
  }
}
