import '../core/api_client.dart';
import '../models/json.dart';
import '../models/place.dart';

/// Endpoints under `/places` and `/guides`: saved places and curated,
/// optionally public/cloneable guide collections.
class GuidesService {
  GuidesService(this._client);

  final ApiClient _client;

  // --- Saved places ---------------------------------------------------------

  /// The current user's saved places.
  Future<List<Place>> places() async =>
      asModelList(await _client.getJson('/places'), Place.fromJson);

  Future<Place> place(String placeId) async => Place.fromJson(
      asMapOrNull(await _client.getJson('/places/$placeId')) ?? const {});

  /// Saves a new place pin.
  Future<Place> addPlace({
    required String title,
    String? notes,
    double? longitude,
    double? latitude,
    String? address,
    String? category,
  }) async =>
      Place.fromJson(asMapOrNull(await _client.postJson('/places', body: {
            'title': title,
            if (notes != null) 'notes': notes,
            if (longitude != null) 'longitude': longitude,
            if (latitude != null) 'latitude': latitude,
            if (address != null) 'address': address,
            if (category != null) 'category': category,
          })) ??
          const {});

  Future<void> deletePlace(String placeId) async {
    await _client.deleteJson('/places/$placeId');
  }

  // --- Guides ---------------------------------------------------------------

  /// The current user's guides.
  Future<List<Guide>> guides() async =>
      asModelList(await _client.getJson('/guides'), Guide.fromJson);

  Future<Guide> createGuide({
    required String name,
    String? color,
    String? icon,
  }) async =>
      Guide.fromJson(asMapOrNull(await _client.postJson('/guides', body: {
            'name': name,
            if (color != null) 'color': color,
            if (icon != null) 'icon': icon,
          })) ??
          const {});

  /// Updates a guide; pass only the fields to change
  /// (`name`, `color`, `is_public`).
  Future<Guide> updateGuide(String guideId, Map<String, dynamic> changes) async =>
      Guide.fromJson(asMapOrNull(
              await _client.patchJson('/guides/$guideId', body: changes)) ??
          const {});

  Future<void> deleteGuide(String guideId) async {
    await _client.deleteJson('/guides/$guideId');
  }

  Future<void> addToGuide(String guideId, String placeId) async {
    await _client.postJson('/guides/$guideId/places/$placeId');
  }

  Future<void> removeFromGuide(String guideId, String placeId) async {
    await _client.deleteJson('/guides/$guideId/places/$placeId');
  }

  // --- Public guides --------------------------------------------------------

  /// A public guide by its shareable [slug] (raw payload with `places`).
  Future<Map<String, dynamic>> publicGuide(String slug) async =>
      asMapOrNull(await _client.getJson('/public/guides/$slug')) ?? const {};

  /// Clones a public guide into the current user's guides.
  Future<void> cloneGuide(String slug) async {
    await _client.postJson('/public/guides/$slug/clone');
  }
}
