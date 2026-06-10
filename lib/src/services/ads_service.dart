import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/promoted`: the advertiser account, campaigns, link & reel ads,
/// ad serving and engagement events.
///
/// Responses are advertiser/serving payloads, returned raw.
class AdsService {
  AdsService(this._client);

  final ApiClient _client;

  Map<String, dynamic> _map(Object? d) => asMapOrNull(d) ?? const {};

  List<Map<String, dynamic>> _list(Object? d, [String? key]) {
    final list = d is Map ? (d[key] ?? d['campaigns'] ?? d['items'] ?? d['data']) : d;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// Promotes a post as a sponsored ad ([budget]/[cpc] in account currency).
  Future<Map<String, dynamic>> promotePost(String postId,
          {required int days, required num budget, required num cpc}) async =>
      _map(await _client.postJson('/posts/$postId/promote',
          body: {'days': days, 'budget': budget, 'cpc': cpc}));

  /// Campaigns as a parsed list.
  Future<List<Map<String, dynamic>>> campaignList() async =>
      _list(await _client.getJson('/promoted/campaigns'), 'campaigns');

  /// The advertiser account (balance, status).
  Future<Map<String, dynamic>> account() async =>
      _map(await _client.getJson('/promoted/account'));

  /// Tops up the ad account balance.
  Future<Map<String, dynamic>> topup(num amount) async =>
      _map(await _client.postJson('/promoted/account/topup', body: {'amount': amount}));

  /// All campaigns.
  Future<dynamic> campaigns() => _client.getJson('/promoted/campaigns');

  // --- Serving ------------------------------------------------------------

  /// Fetches the next ad to show in a placement/slot.
  Future<Map<String, dynamic>> next({String? placement, String? slot}) async =>
      _map(await _client.getJson('/promoted/next',
          query: {'placement': placement, 'slot': slot}));

  /// Records an ad engagement event (impression/click/…) for a promoted post.
  Future<void> postEvent(String postId, String event) async {
    await _client.postJson('/promoted/$postId/event', body: {'type': event});
  }

  Future<void> hidePromoted(String postId) async {
    await _client.postJson('/promoted/$postId/hide');
  }

  Future<void> reportPromoted(String postId) async {
    await _client.postJson('/promoted/$postId/report');
  }

  // --- Link ads -----------------------------------------------------------

  Future<dynamic> linkAds() => _client.getJson('/promoted/links');

  Future<Map<String, dynamic>> createLinkAd(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/promoted/links', body: body));

  Future<void> deleteLinkAd(String adId) async {
    await _client.deleteJson('/promoted/links/$adId');
  }

  Future<void> linkAdEvent(String adId, String event) async {
    await _client.postJson('/promoted/links/$adId/event', body: {'type': event});
  }

  // --- Reel ads -----------------------------------------------------------

  Future<dynamic> reelAds() => _client.getJson('/promoted/reels');

  Future<Map<String, dynamic>> createReelAd(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/promoted/reels', body: body));

  Future<dynamic> serveReelAd() => _client.getJson('/promoted/reels/serve');

  Future<void> deleteReelAd(String adId) async {
    await _client.deleteJson('/promoted/reels/$adId');
  }

  Future<void> reelAdEvent(String adId, String event) async {
    await _client.postJson('/promoted/reels/$adId/event', body: {'type': event});
  }
}
