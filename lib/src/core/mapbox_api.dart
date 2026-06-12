import 'dart:convert';

import 'package:flutter/material.dart';
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

/// GET [url] on the app's own transport and decode the JSON object reply.
/// Null on HTTP errors, empty bodies, and non-JSON bodies (e.g. a proxy or
/// captive portal answering 200 with HTML) — Mapbox failures degrade, they
/// don't crash.
Future<Map<String, dynamic>?> _getJson(String url) async {
  final res = await sendHttp(HttpRequestData(
    method: 'GET',
    url: Uri.parse(url),
    headers: const {'Accept': 'application/json'},
    timeout: const Duration(seconds: 20),
  ));
  if (res.status >= 400 || res.body.isEmpty) return null;
  try {
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : null;
  } on FormatException {
    return null;
  }
}

/// Shared raster tile layer for the app's inline mini-maps (route previews,
/// shared locations). The full map screen manages its own styles. Without a
/// token, a quiet placeholder is shown instead of a grid of broken tiles.
Widget mapboxTileLayer() => hasMapbox
    ? TileLayer(
        urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/'
            'tiles/512/{z}/{x}/{y}@2x?access_token=$kMapboxToken',
        userAgentPackageName: 'ca.okayspace.app',
        tileSize: 512,
        zoomOffset: -1,
      )
    : const ColoredBox(
        color: Color(0xFF2A2D33),
        child: Center(
          child: Text('Map unavailable — missing MAPBOX_TOKEN',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      );

/// Forward-geocodes [query] with the Mapbox Geocoding API, falling back to
/// the backend geocoder only when no token is configured. When a Foursquare
/// key is present, business/POI matches are appended (biased toward [near]).
/// Results use the same shape the UI already consumes:
/// {name, full_address, lat, lng}.
///
/// Never throws: several call sites feed this straight into debounced
/// FutureBuilders with no error branch, so failures resolve to an empty list.
Future<List<Map<String, dynamic>>> geocodePlaces(String query,
    {LatLng? near}) async {
  try {
    if (!hasMapbox) {
      // Backend rows aren't coordinate-filtered at the source; drop the ones
      // a picker couldn't use (saving a place with null coords is worse than
      // not offering it).
      final rows = await api.roadside.geocode(query);
      return [
        for (final r in rows)
          if (_coordOf(r, 'lat', 'latitude') != null &&
              _coordOf(r, 'lng', 'longitude', 'lon') != null)
            r,
      ];
    }
    final fsq = foursquarePlaces(query, near: near); // parallel with Mapbox
    Map<String, dynamic>? data;
    try {
      data = await _getJson(
          'https://api.mapbox.com/geocoding/v5/mapbox.places/'
          '${Uri.encodeComponent(query)}.json'
          '?access_token=$kMapboxToken&limit=6'
          '${near != null ? '&proximity=${near.longitude},${near.latitude}' : ''}');
    } catch (_) {
      // Still consume the already-launched Foursquare future: its results
      // are valid on their own, and abandoning it risks an unhandled error.
      return await fsq;
    }
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
  } catch (_) {
    return const [];
  }
}

double? _coordOf(Map r, String a, String b, [String? c]) {
  final v = r[a] ?? r[b] ?? (c != null ? r[c] : null);
  return v is num ? v.toDouble() : double.tryParse('$v');
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
  final route = routes.first;
  if (route is! Map) return null;
  // A malformed route (missing geometry/distance/duration) reads as "no
  // route" rather than throwing into the caller.
  final geometry = route['geometry'];
  final coordsList = geometry is Map ? geometry['coordinates'] : null;
  final distance = route['distance'];
  final duration = route['duration'];
  if (coordsList is! List || distance is! num || duration is! num) {
    return null;
  }
  final line = <LatLng>[
    for (final c in coordsList)
      if (c is List && c.length >= 2 && c[0] is num && c[1] is num)
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  if (line.length < 2) return null;
  return (
    line: line,
    km: distance / 1000,
    mins: (duration / 60).round(),
  );
}
