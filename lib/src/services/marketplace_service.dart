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

  Map<String, dynamic> _map(Object? d) => asMapOrNull(d) ?? const {};

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

  // --- Business storefront --------------------------------------------------

  /// The current user's business storefront, or an empty map if none.
  Future<Map<String, dynamic>> myBusiness() async =>
      asMapOrNull(await _client.getJson('/marketplace/business/me')) ??
      const {};

  /// Creates or updates the storefront (see `BusinessProfilePatch`: `name`,
  /// `tagline`, `bio`, `logo`, `banner`, `accent`, `category`, `policies`,
  /// `location`, `contact_email`, `contact_phone`, `website`).
  Future<Map<String, dynamic>> upsertBusiness(
          Map<String, dynamic> changes) async =>
      asMapOrNull(
          await _client.putJson('/marketplace/business', body: changes)) ??
      const {};

  Future<void> deleteBusiness() async {
    await _client.deleteJson('/marketplace/business');
  }

  /// A business storefront by id (includes its listings and rating).
  Future<Map<String, dynamic>> business(String businessId) async =>
      asMapOrNull(
          await _client.getJson('/marketplace/business/$businessId')) ??
      const {};

  Future<List<Map<String, dynamic>>> businessReviews(
      String businessId) async {
    final data =
        await _client.getJson('/marketplace/business/$businessId/reviews');
    final list = data is Map ? (data['reviews'] ?? data['items']) : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> addBusinessReview(String businessId,
      {required int rating, String? text}) async {
    await _client.postJson('/marketplace/business/$businessId/reviews',
        body: {'rating': rating, if (text != null) 'text': text});
  }

  /// A seller's marketplace profile (listings + rating).
  Future<Map<String, dynamic>> sellerProfile(String userId) async =>
      asMapOrNull(await _client.getJson('/marketplace/users/$userId')) ??
      const {};

  Future<void> addSellerReview(String userId,
      {required int rating, String? text}) async {
    await _client.postJson('/marketplace/users/$userId/reviews',
        body: {'rating': rating, if (text != null) 'text': text});
  }

  // --- Offers / negotiation -----------------------------------------------

  /// Makes (or updates) an offer on a listing. Re-offering replaces your open
  /// offer rather than stacking duplicates.
  Future<Map<String, dynamic>> makeOffer(String listingId, num amount,
          {String? message}) async =>
      _map(await _client.postJson('/listings/$listingId/offers', body: {
        'amount': amount,
        if (message != null && message.isNotEmpty) 'message': message,
      }));

  /// Offers on a listing: the seller sees all; anyone else sees only their own.
  Future<List<Map<String, dynamic>>> listingOffers(String listingId) async {
    final data = await _client.getJson('/listings/$listingId/offers');
    final list = data is Map ? data['offers'] : data;
    return list is List
        ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  /// The current user's offers, split into `made` (as buyer) and `received`
  /// (on their listings, as seller).
  Future<Map<String, dynamic>> myOffers() async =>
      _map(await _client.getJson('/offers'));

  // Seller actions.
  Future<Map<String, dynamic>> acceptOffer(String offerId) async =>
      _map(await _client.postJson('/offers/$offerId/accept'));

  Future<Map<String, dynamic>> declineOffer(String offerId) async =>
      _map(await _client.postJson('/offers/$offerId/decline'));

  Future<Map<String, dynamic>> counterOffer(String offerId, num amount) async =>
      _map(await _client.postJson('/offers/$offerId/counter', body: {'amount': amount}));

  // Buyer actions.
  Future<Map<String, dynamic>> acceptCounter(String offerId) async =>
      _map(await _client.postJson('/offers/$offerId/accept-counter'));

  Future<Map<String, dynamic>> withdrawOffer(String offerId) async =>
      _map(await _client.postJson('/offers/$offerId/withdraw'));
}
