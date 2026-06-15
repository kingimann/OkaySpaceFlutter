import '../core/api_client.dart';
import '../models/json.dart';

/// Map helpers backed by the API (AI-assisted place search via the local model).
class MapsService {
  MapsService(this._client);

  final ApiClient _client;

  /// Turns a natural-language request ("quiet coffee near me open now") into a
  /// clean place-search keyword using the backend's local AI. Always returns a
  /// usable `search` term (the raw text when the AI isn't configured).
  /// Keys: `search`, `summary`, `open_now`, `ai`.
  Future<Map<String, dynamic>> aiSearch(String query) async =>
      asMapOrNull(await _client
          .postJson('/maps/ai-search', body: {'query': query})) ??
      {'search': query, 'ai': false};
}
