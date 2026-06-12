import '../core/api_client.dart';
import '../models/json.dart';
import '../models/roadside_request.dart';

/// Endpoints under `/roadside`: requesting assistance, helping others and the
/// full request lifecycle.
class RoadsideService {
  RoadsideService(this._client);

  final ApiClient _client;

  RoadsideRequest _req(Object? d) =>
      RoadsideRequest.fromJson(asMapOrNull(d) ?? const {});
  List<RoadsideRequest> _list(Object? d) =>
      asModelList(d, RoadsideRequest.fromJson);

  /// Whether the user is eligible to request/provide roadside help.
  Future<dynamic> eligibility() => _client.getJson('/roadside/eligibility');

  /// A price quote for a service (raw payload).
  Future<dynamic> quote() => _client.getJson('/roadside/quote');

  /// The user's currently active request, if any.
  Future<dynamic> active() => _client.getJson('/roadside/active');

  /// Requests the user has made.
  Future<List<RoadsideRequest>> mine() async =>
      _list(await _client.getJson('/roadside/mine'));

  /// Requests the user is helping with.
  Future<List<RoadsideRequest>> helping() async =>
      _list(await _client.getJson('/roadside/helping'));

  /// Completed request history.
  Future<List<RoadsideRequest>> history() async =>
      _list(await _client.getJson('/roadside/history'));

  /// Open requests near a location.
  Future<List<RoadsideRequest>> nearby({
    required double lat,
    required double lng,
    double? radiusKm,
  }) async =>
      _list(await _client.getJson('/roadside/nearby',
          query: {'lat': lat, 'lng': lng, 'radius_km': radiusKm}));

  /// Geocodes a free-text place query into candidate locations.
  /// Each result is a map with at least `lat`/`lng` and a display name.
  Future<List<Map<String, dynamic>>> geocode(String query) async {
    final data = await _client.getJson('/pub/geocode', query: {'q': query});
    final list = data is Map ? (data['results'] ?? data['items'] ?? data['data']) : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  // --- Live ETA sharing -----------------------------------------------------

  /// Starts a live ETA share; returns the share payload (with `share_id`).
  Future<Map<String, dynamic>> startEta({
    String? name,
    String? destinationName,
    double? destinationLongitude,
    double? destinationLatitude,
    double? initialLongitude,
    double? initialLatitude,
    int? etaMinutes,
    int? ttlMinutes,
  }) async =>
      asMapOrNull(await _client.postJson('/eta', body: {
        if (name != null) 'name': name,
        if (destinationName != null) 'destination_name': destinationName,
        if (destinationLongitude != null)
          'destination_longitude': destinationLongitude,
        if (destinationLatitude != null)
          'destination_latitude': destinationLatitude,
        if (initialLongitude != null) 'initial_longitude': initialLongitude,
        if (initialLatitude != null) 'initial_latitude': initialLatitude,
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
        if (ttlMinutes != null) 'ttl_minutes': ttlMinutes,
      })) ??
      const {};

  /// Updates the live position/ETA on an active share.
  Future<void> updateEta(String shareId,
      {double? longitude, double? latitude, int? etaMinutes}) async {
    await _client.postJson('/eta/$shareId/update', body: {
      if (longitude != null) 'current_longitude': longitude,
      if (latitude != null) 'current_latitude': latitude,
      if (etaMinutes != null) 'eta_minutes': etaMinutes,
    });
  }

  /// Ends an ETA share.
  Future<void> stopEta(String shareId) async {
    await _client.postJson('/eta/$shareId/stop');
  }

  /// Public transit stops/lines near a location (raw payloads).
  Future<List<Map<String, dynamic>>> transitNearby({
    required double lat,
    required double lng,
    double? radius,
  }) async {
    final data = await _client.getJson('/transit/nearby',
        query: {'lat': lat, 'lon': lng, 'radius': radius});
    final list = data is Map
        ? (data['results'] ?? data['stops'] ?? data['items'] ?? data['data'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<RoadsideRequest> get(String requestId) async =>
      _req(await _client.getJson('/roadside/requests/$requestId'));

  /// Creates a roadside request.
  Future<RoadsideRequest> create({
    required String service,
    required double latitude,
    required double longitude,
    String? placeName,
    String? note,
    String? vehicleMake,
    String? vehicleModel,
    String? fuelType,
    String? paymentMethod,
    List<String>? photos,
  }) async =>
      _req(await _client.postJson('/roadside/requests', body: {
        'service': service,
        'latitude': latitude,
        'longitude': longitude,
        if (placeName != null) 'place_name': placeName,
        if (note != null) 'note': note,
        if (vehicleMake != null) 'vehicle_make': vehicleMake,
        if (vehicleModel != null) 'vehicle_model': vehicleModel,
        if (fuelType != null) 'fuel_type': fuelType,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (photos != null && photos.isNotEmpty) 'photos': photos,
      }));

  // --- Lifecycle (helper + requester actions) -----------------------------

  Future<RoadsideRequest> accept(String requestId) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/accept'));

  Future<RoadsideRequest> enroute(String requestId) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/enroute'));

  Future<RoadsideRequest> arrived(String requestId) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/arrived'));

  Future<RoadsideRequest> cancel(String requestId) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/cancel'));

  Future<RoadsideRequest> dispute(String requestId) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/dispute'));

  /// Leaves a review (1–5 stars + optional text) for a completed request.
  Future<RoadsideRequest> review(String requestId,
          {required int rating, String? text}) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/review',
          body: {'rating': rating, if (text != null) 'text': text}));

  /// Submits the completion verification code.
  Future<RoadsideRequest> verify(String requestId, String code) async =>
      _req(await _client.postJson('/roadside/requests/$requestId/verify',
          body: {'code': code}));
}
