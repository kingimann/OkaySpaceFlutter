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
