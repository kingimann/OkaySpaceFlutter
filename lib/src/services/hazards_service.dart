import '../core/api_client.dart';
import '../models/hazard.dart';
import '../models/json.dart';

/// `/hazards` — crowd-reported road incidents (police, accident, traffic, …)
/// with Waze-style confirm/dismiss. Reports cluster by type+location and
/// expire after a couple of hours server-side.
class HazardsService {
  HazardsService(this._client);

  final ApiClient _client;

  Hazard _haz(Object? d) => Hazard.fromJson(asMapOrNull(d) ?? const {});

  /// Reports a hazard of [type] at the given point.
  Future<Hazard> report(String type,
          {required double lat, required double lng}) async =>
      _haz(await _client.postJson('/hazards',
          body: {'type': type, 'latitude': lat, 'longitude': lng}));

  /// Active/own hazards near a point (radius in metres, default server-side).
  Future<List<Hazard>> nearby(
      {required double lat, required double lng, double? radius}) async {
    final data = await _client.getJson('/hazards', query: {
      'latitude': lat,
      'longitude': lng,
      if (radius != null) 'radius': radius,
    });
    final list = asMapOrNull(data)?['hazards'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Hazard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Confirms a hazard is still there (also counts as a report).
  Future<Hazard> confirm(String id) async =>
      _haz(await _client.postJson('/hazards/$id/confirm'));

  /// Marks a hazard as gone.
  Future<Hazard> dismiss(String id) async =>
      _haz(await _client.postJson('/hazards/$id/dismiss'));
}
