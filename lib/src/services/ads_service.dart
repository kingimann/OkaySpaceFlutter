import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/ads`: the advertiser account, campaigns, link & reel ads,
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
      _list(await _client.getJson('/ads/campaigns'), 'campaigns');

  /// The advertiser account (balance, status).
  Future<Map<String, dynamic>> account() async =>
      _map(await _client.getJson('/ads/account'));

  /// Tops up the ad account balance.
  Future<Map<String, dynamic>> topup(num amount) async =>
      _map(await _client.postJson('/ads/account/topup', body: {'amount': amount}));

  /// All campaigns.
  Future<dynamic> campaigns() => _client.getJson('/ads/campaigns');

  // --- Serving ------------------------------------------------------------

  /// Fetches the next ad to show in a placement/slot.
  Future<Map<String, dynamic>> next({String? placement, String? slot}) async =>
      _map(await _client.getJson('/ads/next',
          query: {'placement': placement, 'slot': slot}));

  /// Records an ad engagement event (impression/click/…) for a promoted post.
  Future<void> postEvent(String postId, String event) async {
    await _client.postJson('/ads/$postId/event', body: {'event': event});
  }

  Future<void> hidePromoted(String postId) async {
    await _client.postJson('/ads/$postId/hide');
  }

  Future<void> reportPromoted(String postId) async {
    await _client.postJson('/ads/$postId/report');
  }

  // --- Link ads -----------------------------------------------------------

  Future<dynamic> linkAds() => _client.getJson('/ads/links');

  Future<Map<String, dynamic>> createLinkAd(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/ads/links', body: body));

  Future<void> deleteLinkAd(String adId) async {
    await _client.deleteJson('/ads/links/$adId');
  }

  Future<void> linkAdEvent(String adId, String event) async {
    await _client.postJson('/ads/links/$adId/event', body: {'event': event});
  }

  // --- Reel ads -----------------------------------------------------------

  Future<dynamic> reelAds() => _client.getJson('/ads/reels');

  Future<Map<String, dynamic>> createReelAd(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/ads/reels', body: body));

  Future<dynamic> serveReelAd() => _client.getJson('/ads/reels/serve');

  Future<void> deleteReelAd(String adId) async {
    await _client.deleteJson('/ads/reels/$adId');
  }

  Future<void> reelAdEvent(String adId, String event) async {
    await _client.postJson('/ads/reels/$adId/event', body: {'event': event});
  }
}
