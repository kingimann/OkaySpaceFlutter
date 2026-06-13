import 'json.dart';

/// A roadside-assistance request (fuel, tow, jump, tire, lockout, …).
///
/// Carries the commonly used fields for both the requester and helper views;
/// the full payload is kept in [raw].
class RoadsideRequest {
  const RoadsideRequest({
    required this.id,
    required this.requesterId,
    this.callerName,
    this.helperId,
    required this.service,
    required this.status,
    this.callNumber,
    this.isTest = false,
    this.enRoute = false,
    this.arrived = false,
    required this.longitude,
    required this.latitude,
    this.placeName,
    this.destName,
    this.destLongitude,
    this.destLatitude,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlate,
    this.fuelType,
    this.note,
    this.photos = const [],
    this.beforePhotos = const [],
    this.afterPhotos = const [],
    this.paymentMethod = 'wallet',
    this.price = 0,
    this.tax = 0,
    this.total = 0,
    this.distanceKm,
    this.mine = false,
    this.helping = false,
    this.canReview,
    this.canDispute,
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
    this.raw = const {},
  });

  final String id;
  final String requesterId;
  final String? callerName;
  final String? helperId;
  final String service;
  final String status;
  final int? callNumber;
  final bool isTest;
  final bool enRoute;
  final bool arrived;
  final double longitude;
  final double latitude;
  final String? placeName;
  final String? destName;

  /// Tow destination coordinates (when [service] is a tow), for routing the
  /// drop-off on the map.
  final double? destLongitude;
  final double? destLatitude;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlate;
  final String? fuelType;
  final String? note;
  final List<String> photos;

  /// Before/after job documentation photos uploaded by the helper.
  final List<String> beforePhotos;
  final List<String> afterPhotos;
  final String paymentMethod;
  final num price;
  final num tax;
  final num total;
  final double? distanceKm;
  final bool mine;
  final bool helping;
  final bool? canReview;
  final bool? canDispute;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final Map<String, dynamic> raw;

  bool get isActive => status != 'completed' && status != 'cancelled';

  factory RoadsideRequest.fromJson(Map<String, dynamic> json) => RoadsideRequest(
        id: asString(json['id']),
        requesterId: asString(json['requester_id']),
        callerName: asStringOrNull(json['caller_name']),
        helperId: asStringOrNull(json['helper_id']),
        service: asString(json['service']),
        status: asString(json['status']),
        callNumber: asIntOrNull(json['call_number']),
        isTest: asBool(json['is_test']),
        enRoute: asBool(json['en_route']),
        arrived: asBool(json['arrived']),
        longitude: asDoubleOrNull(json['longitude']) ?? 0,
        latitude: asDoubleOrNull(json['latitude']) ?? 0,
        placeName: asStringOrNull(json['place_name']),
        destName: asStringOrNull(json['dest_name']),
        destLongitude: asDoubleOrNull(json['dest_longitude']),
        destLatitude: asDoubleOrNull(json['dest_latitude']),
        vehicleMake: asStringOrNull(json['vehicle_make']),
        vehicleModel: asStringOrNull(json['vehicle_model']),
        vehicleColor: asStringOrNull(json['vehicle_color']),
        vehiclePlate: asStringOrNull(json['vehicle_plate']),
        fuelType: asStringOrNull(json['fuel_type']),
        note: asStringOrNull(json['note']),
        photos: asStringList(json['photos']),
        beforePhotos: asStringList(json['before_photos']),
        afterPhotos: asStringList(json['after_photos']),
        paymentMethod: asString(json['payment_method'], 'wallet'),
        price: asDoubleOrNull(json['price']) ?? 0,
        tax: asDoubleOrNull(json['tax']) ?? 0,
        total: asDoubleOrNull(json['total']) ?? 0,
        distanceKm: asDoubleOrNull(json['distance_km']),
        mine: asBool(json['mine']),
        helping: asBool(json['helping']),
        canReview: json['can_review'] == null ? null : asBool(json['can_review']),
        canDispute:
            json['can_dispute'] == null ? null : asBool(json['can_dispute']),
        createdAt: asDate(json['created_at']),
        acceptedAt: asDateOrNull(json['accepted_at']),
        completedAt: asDateOrNull(json['completed_at']),
        raw: json,
      );
}
