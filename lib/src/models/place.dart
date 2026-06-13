import 'json.dart';

/// A saved place (pin) belonging to the current user.
class Place {
  const Place({
    required this.id,
    required this.title,
    this.notes,
    this.longitude,
    this.latitude,
    this.address,
    this.category,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String title;
  final String? notes;
  final double? longitude;
  final double? latitude;
  final String? address;
  final String? category;
  final DateTime createdAt;

  /// The complete, unmodified JSON payload.
  final Map<String, dynamic> raw;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        id: asString(json['id'] ?? json['place_id']),
        title: asString(json['title'], 'Place'),
        notes: asStringOrNull(json['notes']),
        longitude: asDoubleOrNull(json['longitude'] ?? json['lng']),
        latitude: asDoubleOrNull(json['latitude'] ?? json['lat']),
        address: asStringOrNull(json['address']),
        category: asStringOrNull(json['category']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}

/// A user's star rating + optional note for a real-world place, shared
/// across users via a stable [placeKey].
class PlaceReview {
  const PlaceReview({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPicture,
    required this.placeKey,
    required this.placeName,
    this.longitude,
    this.latitude,
    required this.rating,
    this.text,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String userId;
  final String userName;
  final String? userPicture;
  final String placeKey;
  final String placeName;
  final double? longitude;
  final double? latitude;

  /// 1–5 stars.
  final int rating;
  final String? text;
  final DateTime createdAt;

  /// The complete, unmodified JSON payload.
  final Map<String, dynamic> raw;

  factory PlaceReview.fromJson(Map<String, dynamic> json) => PlaceReview(
        id: asString(json['id']),
        userId: asString(json['user_id']),
        userName: asString(json['user_name'], 'Someone'),
        userPicture: asStringOrNull(json['user_picture']),
        placeKey: asString(json['place_key']),
        placeName: asString(json['place_name'], 'Place'),
        longitude: asDoubleOrNull(json['longitude']),
        latitude: asDoubleOrNull(json['latitude']),
        rating: asInt(json['rating']),
        text: asStringOrNull(json['text']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}

/// A curated collection of saved places, optionally public via a slug.
class Guide {
  const Guide({
    required this.id,
    required this.name,
    this.color = '',
    this.icon = '',
    this.placeIds = const [],
    this.isPublic = false,
    this.slug,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String color;
  final String icon;
  final List<String> placeIds;
  final bool isPublic;

  /// Shareable slug when [isPublic] (okayspace.ca/guide/<slug>).
  final String? slug;
  final DateTime createdAt;

  /// The complete, unmodified JSON payload.
  final Map<String, dynamic> raw;

  factory Guide.fromJson(Map<String, dynamic> json) => Guide(
        id: asString(json['id'] ?? json['guide_id']),
        name: asString(json['name'], 'Guide'),
        color: asString(json['color']),
        icon: asString(json['icon']),
        placeIds: asStringList(json['place_ids']),
        isPublic: asBool(json['is_public']),
        slug: asStringOrNull(json['slug']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}
