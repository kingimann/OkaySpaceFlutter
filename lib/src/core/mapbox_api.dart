import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// The shared client lives with the UI layer; pragmatic import for the
// no-token fallback only.
import '../ui/common.dart' show api;
import 'foursquare_api.dart';
import 'http_transport.dart';

/// Mapbox is the app's sole mapping provider: tiles, geocoding, and
/// directions. The public token ships at build time via
/// `--dart-define=MAPBOX_TOKEN=pk....`.
const kMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
bool get hasMapbox => kMapboxToken.isNotEmpty;

/// GET [url] on the app's own transport and decode the JSON object reply
/// (null on HTTP errors — Mapbox failures degrade, they don't crash).
Future<Map<String, dynamic>?> _getJson(String url) async {
  final res = await sendHttp(HttpRequestData(
    method: 'GET',
    url: Uri.parse(url),
    headers: const {'Accept': 'application/json'},
    timeout: const Duration(seconds: 20),
  ));
  if (res.status >= 400) return null;
  final data = jsonDecode(res.body);
  return data is Map<String, dynamic> ? data : null;
}

/// Shared raster tile layer for the app's inline mini-maps (route previews,
/// shared locations). The full map screen manages its own styles.
TileLayer mapboxTileLayer() => TileLayer(
      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/'
          'tiles/512/{z}/{x}/{y}@2x?access_token=$kMapboxToken',
      userAgentPackageName: 'ca.okayspace.app',
      tileSize: 512,
      zoomOffset: -1,
    );

/// Forward-geocodes [query] with the Mapbox Geocoding API, falling back to
/// the backend geocoder only when no token is configured. When a Foursquare
/// key is present, business/POI matches are appended (biased toward [near]).
/// Results use the same shape the UI already consumes:
/// {name, full_address, lat, lng}.
Future<List<Map<String, dynamic>>> geocodePlaces(String query,
    {LatLng? near}) async {
  if (!hasMapbox) return api.roadside.geocode(query);
  final fsq = foursquarePlaces(query, near: near); // in parallel with Mapbox
  final data = await _getJson(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${Uri.encodeComponent(query)}.json'
      '?access_token=$kMapboxToken&limit=6'
      '${near != null ? '&proximity=${near.longitude},${near.latitude}' : ''}');
  final features = data?['features'];
  return [
    if (features is List)
      for (final f in features.whereType<Map>())
        if (f['center'] is List && (f['center'] as List).length >= 2)
          {
            'name': f['text'] ?? f['place_name'] ?? 'Result',
            'full_address': f['place_name'] ?? f['text'] ?? '',
            'lng': ((f['center'] as List)[0] as num).toDouble(),
            'lat': ((f['center'] as List)[1] as num).toDouble(),
          },
    // Businesses/POIs from Foursquare, after the address matches.
    ...await fsq,
  ];
}

/// A driving route through [points] from the Mapbox Directions API
/// (driving-traffic profile). Returns the polyline plus distance/duration,
/// or null when no route exists. Throws [StateError] without a token.
Future<({List<LatLng> line, double km, int mins})?> driveRoute(
    List<LatLng> points) async {
  if (!hasMapbox) {
    throw StateError('Mapbox token not configured');
  }
  final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
  final data = await _getJson(
      'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$coords'
      '?overview=full&geometries=geojson&access_token=$kMapboxToken');
  final routes = data?['routes'];
  if (routes is! List || routes.isEmpty) return null;
  final route = routes.first as Map;
  final line = [
    for (final c
        in ((route['geometry'] as Map)['coordinates'] as List).cast<List>())
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  return (
    line: line,
    km: (route['distance'] as num) / 1000,
    mins: ((route['duration'] as num) / 60).round(),
  );
}
