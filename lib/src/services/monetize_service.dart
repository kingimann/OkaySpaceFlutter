import '../core/api_client.dart';
import '../models/json.dart';
import '../models/pub_site.dart';

/// Endpoints under `/pub`: the publisher ad network — register sites, view
/// ad earnings and get the embed snippet (§10 monetize).
class MonetizeService {
  MonetizeService(this._client);

  final ApiClient _client;

  /// The current user's registered publisher sites.
  Future<List<PubSite>> sites() async {
    final data = await _client.getJson('/pub/sites');
    final v = data is Map ? data['sites'] : data;
    return asModelList(v, PubSite.fromJson);
  }

  /// Registers a new publisher site.
  Future<PubSite> createSite({required String name, String? domain}) async =>
      PubSite.fromJson(asMapOrNull(await _client.postJson('/pub/sites', body: {
            'name': name,
            if (domain != null && domain.isNotEmpty) 'domain': domain,
          })) ??
          const {});

  Future<void> deleteSite(String siteId) async {
    await _client.deleteJson('/pub/sites/$siteId');
  }
}
