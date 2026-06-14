import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'http_transport.dart';

/// Foursquare Places — business/POI search, called directly from the app.
///
/// Configure at build time with `--dart-define=FOURSQUARE_KEY=...`. Both key
/// generations are supported: legacy v3 keys (`fsq3...`, sent raw) and the
/// newer service keys (sent as a Bearer token against the current API).
/// Without a key, place search simply contributes no extra results.
const kFoursquareKey = String.fromEnvironment('FOURSQUARE_KEY');

bool get hasFoursquare => kFoursquareKey.isNotEmpty;

bool get _legacyKey => kFoursquareKey.startsWith('fsq3');

/// Searches places near [near] (when given) and returns results in the same
/// shape the app's geocoders use: {name, full_address, lat, lng}. Errors and
/// missing configuration both return an empty list — POI search is an
/// enhancement, never a blocker.
Future<List<Map<String, dynamic>>> foursquarePlaces(String query,
    {LatLng? near, int limit = 5}) async {
  if (!hasFoursquare || query.trim().isEmpty) return const [];
  try {
    final params = 'query=${Uri.encodeQueryComponent(query)}&limit=$limit'
        '${near != null ? '&ll=${near.latitude},${near.longitude}' : ''}';
    final res = await sendHttp(HttpRequestData(
      method: 'GET',
      url: Uri.parse(_legacyKey
          ? 'https://api.foursquare.com/v3/places/search?$params'
          : 'https://places-api.foursquare.com/places/search?$params'),
      headers: {
        'Accept': 'application/json',
        if (_legacyKey)
          'Authorization': kFoursquareKey
        else ...{
          'Authorization': 'Bearer $kFoursquareKey',
          'X-Places-Api-Version': '2025-06-17',
        },
      },
      timeout: const Duration(seconds: 15),
    ));
    if (res.status >= 400) return const [];
    final data = jsonDecode(res.body);
    final results = data is Map ? data['results'] : null;
    if (results is! List) return const [];
    return [
      for (final p in results.whereType<Map>())
        if (_latOf(p) != null && _lngOf(p) != null)
          {
            'name': p['name'] ?? 'Place',
            'full_address': (p['location'] is Map
                    ? (p['location'] as Map)['formatted_address']
                    : null) ??
                '',
            'lat': _latOf(p),
            'lng': _lngOf(p),
          },
    ];
  } catch (_) {
    return const [];
  }
}

/// Places near [near] with no query — a WhatsApp-style "places near you"
/// browse, sorted by distance. Same {name, full_address, lat, lng} shape;
/// empty when unconfigured or on any error.
Future<List<Map<String, dynamic>>> foursquareNearby(LatLng near,
    {int limit = 12, int radiusM = 1500}) async {
  if (!hasFoursquare) return const [];
  try {
    final params = 'll=${near.latitude},${near.longitude}'
        '&radius=$radiusM&limit=$limit&sort=DISTANCE';
    final res = await sendHttp(HttpRequestData(
      method: 'GET',
      url: Uri.parse(_legacyKey
          ? 'https://api.foursquare.com/v3/places/search?$params'
          : 'https://places-api.foursquare.com/places/search?$params'),
      headers: {
        'Accept': 'application/json',
        if (_legacyKey)
          'Authorization': kFoursquareKey
        else ...{
          'Authorization': 'Bearer $kFoursquareKey',
          'X-Places-Api-Version': '2025-06-17',
        },
      },
      timeout: const Duration(seconds: 15),
    ));
    if (res.status >= 400) return const [];
    final data = jsonDecode(res.body);
    final results = data is Map ? data['results'] : null;
    if (results is! List) return const [];
    return [
      for (final p in results.whereType<Map>())
        if (_latOf(p) != null && _lngOf(p) != null)
          {
            'name': p['name'] ?? 'Place',
            'full_address': (p['location'] is Map
                    ? (p['location'] as Map)['formatted_address']
                    : null) ??
                '',
            'lat': _latOf(p),
            'lng': _lngOf(p),
          },
    ];
  } catch (_) {
    return const [];
  }
}

// Coordinates live under geocodes.main (v3) or flat latitude/longitude (new).
double? _numOf(Object? v) => v is num ? v.toDouble() : null;

double? _latOf(Map p) {
  final geo = p['geocodes'];
  if (geo is Map && geo['main'] is Map) {
    return _numOf((geo['main'] as Map)['latitude']);
  }
  return _numOf(p['latitude']);
}

double? _lngOf(Map p) {
  final geo = p['geocodes'];
  if (geo is Map && geo['main'] is Map) {
    return _numOf((geo['main'] as Map)['longitude']);
  }
  return _numOf(p['longitude']);
}
