import '../core/api_client.dart';
import '../models/json.dart';
import '../models/listing.dart';
import '../models/message.dart';

/// Endpoints under `/listings` and `/marketplace`: browsing, listing
/// management, comments, saving and contacting sellers.
class MarketplaceService {
  MarketplaceService(this._client);

  final ApiClient _client;

  Listing _listing(Object? d) => Listing.fromJson(asMapOrNull(d) ?? const {});

  /// Browses listings with optional filters (category, query, price range,
  /// condition, geo radius, sort…).
  Future<List<Listing>> listings({
    String? category,
    String? query,
    String? status,
    String? condition,
    num? minPrice,
    num? maxPrice,
    String? sort,
    double? lat,
    double? lng,
    double? radiusKm,
  }) async =>
      asModelList(
        await _client.getJson('/listings', query: {
          'category': category,
          'q': query,
          'status': status,
          'condition': condition,
          'min_price': minPrice,
          'max_price': maxPrice,
          'sort': sort,
          'lat': lat,
          'lng': lng,
          'radius_km': radiusKm,
        }),
        Listing.fromJson,
      );

  /// Listings the current user has saved.
  Future<List<Listing>> saved() async =>
      asModelList(await _client.getJson('/listings/saved'), Listing.fromJson);

  /// Listings posted by a user.
  Future<List<Listing>> userListings(String userId) async => asModelList(
      await _client.getJson('/listings/user/$userId'), Listing.fromJson);

  Future<Listing> get(String listingId) async =>
      _listing(await _client.getJson('/listings/$listingId'));

  Future<Listing> create(ListingCreate listing) async =>
      _listing(await _client.postJson('/listings', body: listing.toJson()));

  Future<Listing> update(String listingId, Map<String, dynamic> changes) async =>
      _listing(await _client.patchJson('/listings/$listingId', body: changes));

  Future<void> delete(String listingId) async {
    await _client.deleteJson('/listings/$listingId');
  }

  // --- Engagement ---------------------------------------------------------

  Future<Listing> toggleLike(String listingId) async =>
      _listing(await _client.postJson('/listings/$listingId/like'));

  Future<void> save(String listingId) async {
    await _client.postJson('/listings/$listingId/save');
  }

  Future<void> unsave(String listingId) async {
    await _client.deleteJson('/listings/$listingId/save');
  }

  Future<void> report(String listingId, String reason) async {
    await _client.postJson('/listings/$listingId/report',
        body: {'reason': reason});
  }

  /// Starts (or fetches) a conversation with the seller about a listing.
  Future<ConversationView> contactSeller(String listingId) async =>
      ConversationView.fromJson(
          asMapOrNull(await _client.postJson('/listings/$listingId/contact')) ??
              const {});

  // --- Comments -----------------------------------------------------------

  Future<List<ListingComment>> comments(String listingId) async => asModelList(
      await _client.getJson('/listings/$listingId/comments'),
      ListingComment.fromJson);

  Future<ListingComment> addComment(String listingId, String text,
          {String? parentId}) async =>
      ListingComment.fromJson(asMapOrNull(
              await _client.postJson('/listings/$listingId/comments', body: {
            'text': text,
            if (parentId != null) 'parent_id': parentId,
          })) ??
          const {});

  Future<void> deleteComment(String listingId, String commentId) async {
    await _client.deleteJson('/listings/$listingId/comments/$commentId');
  }

  Future<ListingComment> likeComment(String listingId, String commentId) async =>
      ListingComment.fromJson(asMapOrNull(await _client
              .postJson('/listings/$listingId/comments/$commentId/like')) ??
          const {});
}
