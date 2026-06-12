import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// One GPS fix with the extras a map can render: accuracy ring, compass
/// heading (degrees, NaN/0 when unknown), and speed in m/s.
class GeoFix {
  const GeoFix(this.point, {this.accuracyM = 0, this.heading = 0, this.speedMs = 0});
  final LatLng point;
  final double accuracyM;
  final double heading;
  final double speedMs;

  double get speedKmh => speedMs * 3.6;
}

GeoFix _fix(Position p) => GeoFix(
      LatLng(p.latitude, p.longitude),
      accuracyM: p.accuracy.isFinite ? p.accuracy : 0,
      heading: p.heading.isFinite ? p.heading : 0,
      speedMs: p.speed.isFinite && p.speed > 0 ? p.speed : 0,
    );

/// The device's current position, or null when the platform/user says no
/// (services off, permission denied, web without HTTPS, timeout). Callers
/// always need a fallback, so failures are soft.
Future<GeoFix?> currentFix() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return _fix(pos);
  } catch (_) {
    return null;
  }
}

/// Back-compat point-only variant.
Future<LatLng?> currentLatLng() async => (await currentFix())?.point;

/// Continuous fixes (~every 5 m, high accuracy). Permission must already be
/// granted (call [currentFix] first); errors end the stream silently.
Stream<GeoFix> fixStream() => Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).map(_fix).handleError((Object _) {});

/// Back-compat point-only stream.
Stream<LatLng> positionStream() => fixStream().map((f) => f.point);
