import 'json.dart';

/// A crowd-reported road hazard/incident (police, accident, traffic, …),
/// Waze-style. Shown on the map and reportable while navigating.
class Hazard {
  const Hazard({
    required this.id,
    required this.type,
    required this.longitude,
    required this.latitude,
    this.confirmations = 0,
    this.dismissals = 0,
    this.status = 'pending',
    this.mine = false,
  });

  final String id;
  final String type;
  final double longitude;
  final double latitude;
  final int confirmations;
  final int dismissals;
  final String status; // pending | active
  final bool mine;

  factory Hazard.fromJson(Map<String, dynamic> json) => Hazard(
        id: asString(json['id']),
        type: asString(json['type']),
        longitude: asDoubleOrNull(json['longitude']) ?? 0,
        latitude: asDoubleOrNull(json['latitude']) ?? 0,
        confirmations: asInt(json['confirmations']),
        dismissals: asInt(json['dismissals']),
        status: asString(json['status'], 'pending'),
        mine: asBool(json['mine']),
      );
}
