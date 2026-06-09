import 'json.dart';
import 'post.dart';

/// A marketplace listing.
class Listing {
  const Listing({
    required this.id,
    required this.userId,
    required this.seller,
    required this.title,
    this.price = 0,
    this.currency = 'USD',
    this.category = '',
    this.condition,
    this.description,
    this.photos = const [],
    this.longitude,
    this.latitude,
    this.locality,
    this.negotiable = false,
    this.quantity = 1,
    this.brand,
    this.delivery,
    this.distanceKm,
    this.status = 'active',
    this.viewsCount = 0,
    this.savedCount = 0,
    this.savedByMe = false,
    this.likesCount = 0,
    this.likedByMe = false,
    this.commentsCount = 0,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String userId;
  final PostAuthor seller;
  final String title;
  final num price;
  final String currency;
  final String category;
  final String? condition;
  final String? description;
  final List<String> photos;
  final double? longitude;
  final double? latitude;
  final String? locality;
  final bool negotiable;
  final int quantity;
  final String? brand;
  final String? delivery;
  final double? distanceKm;
  final String status;
  final int viewsCount;
  final int savedCount;
  final bool savedByMe;
  final int likesCount;
  final bool likedByMe;
  final int commentsCount;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory Listing.fromJson(Map<String, dynamic> json) => Listing(
        id: asString(json['id']),
        userId: asString(json['user_id']),
        seller: PostAuthor.fromJson(asMapOrNull(json['seller']) ?? const {}),
        title: asString(json['title']),
        price: asDoubleOrNull(json['price']) ?? 0,
        currency: asString(json['currency'], 'USD'),
        category: asString(json['category']),
        condition: asStringOrNull(json['condition']),
        description: asStringOrNull(json['description']),
        photos: asStringList(json['photos']),
        longitude: asDoubleOrNull(json['longitude']),
        latitude: asDoubleOrNull(json['latitude']),
        locality: asStringOrNull(json['locality']),
        negotiable: asBool(json['negotiable']),
        quantity: asInt(json['quantity'], 1),
        brand: asStringOrNull(json['brand']),
        delivery: asStringOrNull(json['delivery']),
        distanceKm: asDoubleOrNull(json['distance_km']),
        status: asString(json['status'], 'active'),
        viewsCount: asInt(json['views_count']),
        savedCount: asInt(json['saved_count']),
        savedByMe: asBool(json['saved_by_me']),
        likesCount: asInt(json['likes_count']),
        likedByMe: asBool(json['liked_by_me']),
        commentsCount: asInt(json['comments_count']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}

/// Request body for creating a listing.
class ListingCreate {
  const ListingCreate({
    required this.title,
    required this.price,
    required this.category,
    this.currency = 'USD',
    this.condition,
    this.description,
    this.photos = const [],
    this.longitude,
    this.latitude,
    this.locality,
    this.negotiable = false,
    this.quantity = 1,
    this.brand,
    this.delivery,
    this.contactEmail,
    this.contactPhone,
    this.businessId,
  });

  final String title;
  final num price;
  final String category;
  final String currency;
  final String? condition;
  final String? description;
  final List<String> photos;
  final double? longitude;
  final double? latitude;
  final String? locality;
  final bool negotiable;
  final int quantity;
  final String? brand;
  final String? delivery;
  final String? contactEmail;
  final String? contactPhone;
  final String? businessId;

  Map<String, dynamic> toJson() => {
        'title': title,
        'price': price,
        'category': category,
        'currency': currency,
        if (condition != null) 'condition': condition,
        if (description != null) 'description': description,
        if (photos.isNotEmpty) 'photos': photos,
        if (longitude != null) 'longitude': longitude,
        if (latitude != null) 'latitude': latitude,
        if (locality != null) 'locality': locality,
        'negotiable': negotiable,
        'quantity': quantity,
        if (brand != null) 'brand': brand,
        if (delivery != null) 'delivery': delivery,
        if (contactEmail != null) 'contact_email': contactEmail,
        if (contactPhone != null) 'contact_phone': contactPhone,
        if (businessId != null) 'business_id': businessId,
      };
}

/// A comment on a listing.
class ListingComment {
  const ListingComment({
    required this.id,
    required this.listingId,
    required this.author,
    required this.text,
    this.parentId,
    this.likesCount = 0,
    this.likedByMe = false,
    this.repliesCount = 0,
    this.mine = false,
    this.editedAt,
    required this.createdAt,
  });

  final String id;
  final String listingId;
  final PostAuthor author;
  final String text;
  final String? parentId;
  final int likesCount;
  final bool likedByMe;
  final int repliesCount;
  final bool mine;
  final DateTime? editedAt;
  final DateTime createdAt;

  factory ListingComment.fromJson(Map<String, dynamic> json) => ListingComment(
        id: asString(json['id']),
        listingId: asString(json['listing_id']),
        author: PostAuthor.fromJson(asMapOrNull(json['author']) ?? const {}),
        text: asString(json['text']),
        parentId: asStringOrNull(json['parent_id']),
        likesCount: asInt(json['likes_count']),
        likedByMe: asBool(json['liked_by_me']),
        repliesCount: asInt(json['replies_count']),
        mine: asBool(json['mine']),
        editedAt: asDateOrNull(json['edited_at']),
        createdAt: asDate(json['created_at']),
      );
}
