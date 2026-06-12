import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// The device's current position, or null when the platform/user says no
/// (services off, permission denied, web without HTTPS, timeout). Callers
/// always need a fallback, so failures are soft.
Future<LatLng?> currentLatLng() async {
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
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}
