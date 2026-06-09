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
