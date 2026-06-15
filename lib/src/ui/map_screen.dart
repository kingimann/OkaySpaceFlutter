import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/device_location.dart';
import '../core/mapbox_api.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'eta_view_screen.dart';
import 'marketplace_screen.dart';
import 'navigation_screen.dart';
import 'place_reviews_screen.dart';

/// Mapbox public access token, injected at build time via
/// `--dart-define=MAPBOX_TOKEN=pk...`. Mapbox is the only map provider;
/// without a token the map screen shows a configuration notice instead.
String get _mapboxToken => kMapboxToken;
bool get _hasMapbox => hasMapbox;

/// A selectable Mapbox basemap style.
class _TileStyle {
  const _TileStyle(this.id, this.label,
      {required this.mapboxStyle, this.dark = false});
  final String id;
  final String label;
  final String mapboxStyle;
  final bool dark;

  String get tileUrl =>
      'https://api.mapbox.com/styles/v1/mapbox/$mapboxStyle/tiles/512/{z}/{x}/{y}@2x?access_token=$_mapboxToken';
}

const _mapboxStyles = <_TileStyle>[
  _TileStyle('streets', 'Streets', mapboxStyle: 'streets-v12'),
  _TileStyle('outdoors', 'Outdoors', mapboxStyle: 'outdoors-v12'),
  _TileStyle('satellite', 'Satellite',
      mapboxStyle: 'satellite-streets-v12', dark: true),
  _TileStyle('light', 'Light', mapboxStyle: 'light-v11'),
  _TileStyle('dark', 'Dark', mapboxStyle: 'dark-v11', dark: true),
];

/// An interactive map with switchable layers — marketplace listings, open
/// roadside requests and nearby transit — plus location search and an
/// adjustable radius. Tiles, geocoding and directions are all Mapbox.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.embedded = false});

  /// True as a home tab (shell provides the nav); false when pushed standalone.
  final bool embedded;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // Default view (Toronto) until the user searches or pans.
  static const _fallback = LatLng(43.6532, -79.3832);

  final _controller = MapController();
  final _storage = const FlutterSecureStorage();

  LatLng _center = _fallback;
  double _radiusKm = 25;
  bool _showListings = true;
  bool _showRoadside = false;
  bool _showTransit = false;
  bool _showSaved = false;
  bool _showRated = false; // top-rated places (from /reviews/nearby)
  bool _loading = false;

  // Display options (persisted).
  String _tileStyle = 'streets';
  bool _showRadiusCircle = true;
  bool _showCrosshair = false;
  bool _cluster = false;
  bool _searchAsIMove = false;
  // Inline top search: type directly in the top bar; results drop down beneath
  // it (no bottom sheet).
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Map<String, dynamic>> _searchResults = const [];
  bool _searchBusy = false;
  bool _searchAiBusy = false;
  bool _searchActive = false; // dropdown showing (field focused / has results)
  int _searchSeq = 0;
  Timer? _searchDebounce;
  bool _showGrid = false; // lat/lng graticule
  bool _showLabels = false; // marker title labels
  bool _rotationLocked = false;
  double _pinSize = 38;
  String _units = 'km'; // 'km' | 'mi'

  // Filters.
  double _maxPrice = 0; // 0 = no max
  double _minPrice = 0;
  bool _withPhotosOnly = false;
  String _roadsideStatus = 'all';
  String _savedCategory = 'all';
  String _nearestSort = 'distance'; // 'distance' | 'price' | 'name'

  // Cached zoom so build/cluster code never touches the controller before its
  // first frame (which would throw).
  double _liveZoom = 11;
  bool _mapReady = false;

  // Top/bottom chrome auto-hides (animated, via the global bars controller)
  // while the user pans or zooms the map.
  Timer? _chromeTimer;

  // The last search result: a visible pin + result card with directions.
  LatLng? _searchPin;
  String? _searchLabel;
  String? _searchAddress;

  // In-app road route (OSRM) from the location dot to the search pin.
  List<LatLng> _roadRoute = const [];
  String? _routeSummary;
  bool _locating = false;

  // Latest rich fix: accuracy ring radius, compass heading, speed.
  double _gpsAccuracyM = 0;
  double _gpsHeading = 0;
  double _gpsSpeedKmh = 0;

  void _applyFix(GeoFix fix) {
    _myLocation = fix.point;
    _gpsAccuracyM = fix.accuracyM;
    _gpsHeading = fix.heading;
    _gpsSpeedKmh = fix.speedKmh;
  }

  // Always-on live location: a GPS stream keeps the blue dot tracking the
  // user from the moment the map opens (no follow "mode" to enable). The dot
  // glides between fixes so it never snaps.
  StreamSubscription<GeoFix>? _locSub;
  AnimationController? _dotAnim; // glides the dot between GPS fixes
  AnimationController? _camAnim; // eased camera recenter

  /// Smoothly glides the live dot from where it is to [dest], so a new GPS
  /// fix doesn't jump. One reusable controller: a fresh fix restarts the
  /// glide from the current interpolated point.
  void _glideDotTo(LatLng dest) {
    final from = _myLocation ?? dest;
    if (from.latitude == dest.latitude && from.longitude == dest.longitude) {
      setState(() => _myLocation = dest);
      return;
    }
    _dotAnim?.dispose();
    final ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _dotAnim = ctl;
    final curve = CurvedAnimation(parent: ctl, curve: Curves.easeOut);
    final latT = Tween<double>(begin: from.latitude, end: dest.latitude);
    final lngT = Tween<double>(begin: from.longitude, end: dest.longitude);
    ctl.addListener(() {
      final t = curve.value;
      setState(
          () => _myLocation = LatLng(latT.transform(t), lngT.transform(t)));
    });
    ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        ctl.dispose();
        if (identical(_dotAnim, ctl)) _dotAnim = null;
      }
    });
    ctl.forward();
  }

  /// Eased camera move to [dest] at [zoom] — used by the locate button so the
  /// recenter glides instead of teleporting.
  void _animateCamera(LatLng dest, double zoom) {
    if (!_mapReady) {
      _controller.move(dest, zoom);
      return;
    }
    final cam = _controller.camera;
    _camAnim?.dispose();
    final ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _camAnim = ctl;
    final curve = CurvedAnimation(parent: ctl, curve: Curves.easeInOut);
    final latT = Tween<double>(begin: cam.center.latitude, end: dest.latitude);
    final lngT =
        Tween<double>(begin: cam.center.longitude, end: dest.longitude);
    final zT = Tween<double>(begin: cam.zoom, end: zoom);
    ctl.addListener(() {
      final t = curve.value;
      _controller.move(
          LatLng(latT.transform(t), lngT.transform(t)), zT.transform(t));
    });
    ctl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        ctl.dispose();
        if (identical(_camAnim, ctl)) _camAnim = null;
      }
    });
    ctl.forward();
  }

  /// Recenters the camera on the live dot (the locate button). Smoothly zooms
  /// in if we're currently far out.
  void _recenterOnMe() {
    final me = _myLocation;
    if (me == null) {
      _startLiveLocation();
      return;
    }
    final z = _mapReady ? _controller.camera.zoom : 11.0;
    _animateCamera(me, z < 14 ? 16 : z);
  }

  // Multi-stop route (waypoints) + straight-line directions target.
  bool _routing = false;
  final List<LatLng> _route = [];
  LatLng? _directionsTo;

  // Polygon area-measure mode.
  bool _areaMode = false;
  final List<LatLng> _areaPoints = [];

  // Recent searches (persisted).
  List<String> _recent = [];

  // Saved view bookmarks (persisted): {name, lat, lng, zoom}.
  List<Map<String, dynamic>> _bookmarks = [];

  // A manually-set "my location" pin (persisted) and identify pin.
  LatLng? _myLocation;
  LatLng? _identify;

  // Distance-measure tool.
  bool _measuring = false;
  final List<LatLng> _measurePoints = [];

  List<Listing> _listings = const [];
  List<RoadsideRequest> _roadside = const [];
  List<Map<String, dynamic>> _transit = const [];
  List<Map<String, dynamic>> _transitDepartures = const [];
  List<Place> _saved = const [];
  List<NearbyRatedPlace> _rated = const [];

  /// Active live-ETA share id, when sharing.
  String? _etaShareId;
  String? _etaDestination;

  /// Destination coords for the active share (for recomputing the live ETA),
  /// the GPS subscription pushing position, and a throttle on those pushes.
  LatLng? _etaDest;
  StreamSubscription<GeoFix>? _etaSub;
  DateTime _lastEtaPush = DateTime.fromMillisecondsSinceEpoch(0);

  static const _prefsKey = 'okayspace.map.prefs';
  static const _recentKey = 'okayspace.map.recent';
  static const _bookmarksKey = 'okayspace.map.bookmarks';
  static const _myLocKey = 'okayspace.map.mylocation';

  // Zoom to restore once the map is ready (from the last saved view).
  double? _restoreZoom;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadAll();
    // Live location is always on — start tracking the moment the map opens.
    _startLiveLocation();
    // Show the results dropdown as soon as the top search field gains focus.
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && !_searchActive) {
        setState(() => _searchActive = true);
      }
    });
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _dotAnim?.dispose();
    _camAnim?.dispose();
    _etaSub?.cancel();
    _chromeTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    // Don't leave the bars hidden if we leave mid-pan.
    showBars();
    _controller.dispose();
    super.dispose();
  }

  /// The top bar and bottom nav now stay pinned on the map (they no longer
  /// hide while panning), matching the rest of the app.
  void _onMapGesture() {}

  Future<void> _loadPrefs() async {
    try {
      final p = await _storage.read(key: _prefsKey);
      final r = await _storage.read(key: _recentKey);
      final b = await _storage.read(key: _bookmarksKey);
      final m = await _storage.read(key: _myLocKey);
      if (!mounted) return;
      setState(() {
        if (p != null && p.isNotEmpty) {
          final d = jsonDecode(p) as Map<String, dynamic>;
          _tileStyle = d['tile'] as String? ?? 'streets';
          _radiusKm = (d['radius'] as num?)?.toDouble() ?? 25;
          _showListings = d['listings'] as bool? ?? true;
          _showRoadside = d['roadside'] as bool? ?? false;
          _showTransit = d['transit'] as bool? ?? false;
          _showSaved = d['saved'] as bool? ?? false;
          _showRated = d['rated'] as bool? ?? false;
          _showRadiusCircle = d['radiusCircle'] as bool? ?? true;
          _showCrosshair = d['crosshair'] as bool? ?? false;
          _cluster = d['cluster'] as bool? ?? false;
          _showGrid = d['grid'] as bool? ?? false;
          _showLabels = d['labels'] as bool? ?? false;
          _rotationLocked = d['rotLock'] as bool? ?? false;
          _pinSize = (d['pinSize'] as num?)?.toDouble() ?? 38;
          _units = d['units'] as String? ?? 'km';
          final lat = (d['lastLat'] as num?)?.toDouble();
          final lng = (d['lastLng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _center = LatLng(lat, lng);
            _restoreZoom = (d['lastZoom'] as num?)?.toDouble();
          }
        }
        if (r != null && r.isNotEmpty) {
          _recent = r.split('\n').where((s) => s.isNotEmpty).toList();
        }
        if (b != null && b.isNotEmpty) {
          _bookmarks = (jsonDecode(b) as List).cast<Map<String, dynamic>>();
        }
        if (m != null && m.isNotEmpty) {
          final d = jsonDecode(m) as Map<String, dynamic>;
          _myLocation =
              LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble());
        }
      });
      if (_showSaved) _loadSaved();
      // Zoom restore happens in onMapReady once the controller is live.
      if (_mapReady && _restoreZoom != null) {
        _controller.move(_center, _restoreZoom!);
        _restoreZoom = null;
      }
    } catch (_) {/* ignore */}
  }

  void _savePrefs() {
    final cam = _controller.camera;
    _storage
        .write(
            key: _prefsKey,
            value: jsonEncode({
              'tile': _tileStyle,
              'radius': _radiusKm,
              'listings': _showListings,
              'roadside': _showRoadside,
              'transit': _showTransit,
              'saved': _showSaved,
              'rated': _showRated,
              'radiusCircle': _showRadiusCircle,
              'crosshair': _showCrosshair,
              'cluster': _cluster,
              'grid': _showGrid,
              'labels': _showLabels,
              'rotLock': _rotationLocked,
              'pinSize': _pinSize,
              'units': _units,
              'lastLat': cam.center.latitude,
              'lastLng': cam.center.longitude,
              'lastZoom': cam.zoom,
            }))
        .ignore();
  }

  Future<void> _loadSaved() async {
    try {
      final places = await api.guides.places();
      if (mounted) setState(() => _saved = places);
    } catch (_) {/* ignore */}
  }

  void _addRecent(String q) {
    if (q.trim().isEmpty) return;
    setState(() {
      _recent.remove(q);
      _recent.insert(0, q);
      if (_recent.length > 8) _recent = _recent.sublist(0, 8);
    });
    _storage.write(key: _recentKey, value: _recent.join('\n')).ignore();
  }

  void _clearRecents() {
    setState(() => _recent = []);
    _storage.delete(key: _recentKey).ignore();
  }

  int _tileErrors = 0;
  bool _warnedTiles = false;
  DateTime? _lastTileError;

  List<_TileStyle> get _styles => _mapboxStyles;

  _TileStyle get _style => _styles.firstWhere((s) => s.id == _tileStyle,
      orElse: () => _styles.first);

  void _onTileError() {
    // A burst of failures means a bad token/config; isolated blips spread
    // over the session shouldn't accumulate into a false alarm.
    final now = DateTime.now();
    if (_lastTileError != null &&
        now.difference(_lastTileError!) > const Duration(minutes: 2)) {
      _tileErrors = 0;
    }
    _lastTileError = now;
    _tileErrors++;
    if (_tileErrors < 6 || _warnedTiles) return;
    _warnedTiles = true;
    showInfo(context,
        'Map tiles are failing — check the Mapbox token (URL restrictions?).');
  }

  /// Distinct categories of saved places, prefixed with 'all'.
  List<String> get _savedCategories => [
        'all',
        ...{
          for (final p in _saved)
            if (p.category != null && p.category!.isNotEmpty) p.category!
        }
      ];

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final lat = _center.latitude, lng = _center.longitude;
    // Each layer loads independently so one failing (e.g. transit) doesn't
    // wipe out the others.
    final results = await Future.wait([
      _showListings
          ? api.marketplace
              .listings(lat: lat, lng: lng, radiusKm: _radiusKm)
              .catchError((_) => <Listing>[])
          : Future.value(const <Listing>[]),
      _showRoadside
          ? api.roadside
              .nearby(lat: lat, lng: lng, radiusKm: _radiusKm)
              .catchError((_) => <RoadsideRequest>[])
          : Future.value(const <RoadsideRequest>[]),
      _showTransit
          // Transit radius is in metres and the API caps it at 100–2000.
          ? api.roadside
              .transitInfo(
                  lat: lat,
                  lng: lng,
                  radius: (_radiusKm * 1000).clamp(100, 2000).toDouble())
              .catchError((_) => <String, dynamic>{})
          : Future.value(const <String, dynamic>{}),
      _showRated
          ? api.guides
              .nearbyRatedPlaces(lat: lat, lng: lng, radiusKm: _radiusKm)
              .catchError((_) => <NearbyRatedPlace>[])
          : Future.value(const <NearbyRatedPlace>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _listings = results[0] as List<Listing>;
      _roadside = results[1] as List<RoadsideRequest>;
      final transit = results[2] as Map<String, dynamic>;
      _transit = _mapList(transit['stops']);
      _transitDepartures = _mapList(transit['departures']);
      _rated = results[3] as List<NearbyRatedPlace>;
      _loading = false;
    });
  }

  /// Parses "lat, lng" coordinate input; returns null if not coordinates.
  LatLng? _parseCoords(String q) {
    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$')
        .firstMatch(q);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return LatLng(lat, lng);
  }

  void _gotoResult(Map<String, dynamic> r) {
    final lat = (r['lat'] ?? r['latitude']);
    final lng = (r['lng'] ?? r['lon'] ?? r['longitude']);
    final dLat = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final dLng = lng is num ? lng.toDouble() : double.tryParse('$lng');
    if (dLat == null || dLng == null) {
      showInfo(context, 'Could not locate that place.');
      return;
    }
    setState(() {
      _center = LatLng(dLat, dLng);
      _searchPin = _center;
      _searchLabel =
          '${r['name'] ?? r['full_address'] ?? r['display_name'] ?? 'Result'}';
      final addr = (r['full_address'] ?? r['display_name'])?.toString();
      // Only show the address line when it adds something beyond the title.
      _searchAddress = (addr != null && addr.isNotEmpty && addr != _searchLabel)
          ? addr
          : null;
    });
    // Addresses deserve a street-level zoom; a bare camera move with no pin
    // looked like the search did nothing.
    _controller.move(_center, 15);
    _loadAll();
  }

  /// Acquires the device location and keeps the blue dot live from then on.
  /// Safe to call repeatedly: it re-primes a fix and recenters, but only ever
  /// opens one position stream. Called once on open and by the locate button
  /// (and directions) when no fix exists yet.
  Future<void> _startLiveLocation() async {
    if (_locSub == null) setState(() => _locating = true);
    final fix = await currentFix();
    if (!mounted) return;
    if (_locating) setState(() => _locating = false);
    if (fix == null) return; // permission/services off — dot just stays hidden
    setState(() {
      _applyFix(fix);
      _center = fix.point;
    });
    if (_mapReady) {
      final z = _controller.camera.zoom;
      _animateCamera(fix.point, z < 13 ? 15 : z);
    }
    _loadAll();
    if (_locSub != null) return; // stream already live — don't double-subscribe
    _locSub = fixStream().listen((f) {
      if (!mounted) return;
      _gpsAccuracyM = f.accuracyM;
      _gpsHeading = f.heading;
      _gpsSpeedKmh = f.speedKmh;
      _center = f.point;
      _glideDotTo(f.point); // glide, don't snap
    });
  }

  /// Fetches a Mapbox driving-traffic route through [points] and draws it
  /// with a distance/time summary.
  Future<void> _fetchDriveRoute(List<LatLng> points) async {
    if (points.length < 2) return;
    try {
      final r = await driveRoute(points);
      if (r == null) {
        if (mounted) showInfo(context, 'No drivable route found.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _roadRoute = r.line;
        _routeSummary =
            '${r.km.toStringAsFixed(1)} km · ~${r.mins} min drive (live traffic)';
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// In-app directions to [to]: draws the route on our map and lists the
  /// turn-by-turn steps in a sheet — no leaving the app. Falls back to the
  /// external maps app when Mapbox isn't configured.
  Future<void> _directionsInApp(LatLng to,
      {List<({LatLng point, String label})> stops = const []}) async {
    if (!hasMapbox) {
      _openExternal(to);
      return;
    }
    if (_myLocation == null) {
      await _startLiveLocation();
      if (_myLocation == null) {
        if (mounted) {
          showInfo(context,
              'Allow location access to get directions from where you are.');
        }
        return;
      }
    }
    try {
      final r = await driveRoute(
          [_myLocation!, for (final s in stops) s.point, to]);
      if (r == null) {
        if (mounted) showInfo(context, 'No drivable route found.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _roadRoute = r.line;
        _routeSummary =
            '${r.km.toStringAsFixed(1)} km · ~${r.mins} min drive (live traffic)';
      });
      _controller.fitCamera(CameraFit.coordinates(
          coordinates: r.line, padding: const EdgeInsets.all(70)));
      _showStepsSheet(to, r, stops);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Compact search sheet that returns a picked place (used to add a stop).
  Future<({LatLng point, String label})?> _pickStop() async {
    final ctrl = TextEditingController();
    var results = const <Map<String, dynamic>>[];
    Timer? debounce;
    final picked = await showModalBottomSheet<({LatLng point, String label})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (c, setS) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Add a stop',
                      prefixIcon: Icon(Icons.add_location_alt_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      debounce?.cancel();
                      if (v.trim().length < 3) {
                        setS(() => results = const []);
                        return;
                      }
                      debounce =
                          Timer(const Duration(milliseconds: 350), () async {
                        final r = await geocodePlaces(v.trim(),
                            near: _myLocation ?? _center);
                        if (c.mounted) {
                          setS(() => results = r.cast<Map<String, dynamic>>());
                        }
                      });
                    },
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in results.take(8))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text('${r['name'] ?? 'Result'}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            final lat = _num(r['lat'] ?? r['latitude']);
                            final lng =
                                _num(r['lng'] ?? r['lon'] ?? r['longitude']);
                            if (lat == null || lng == null) return;
                            Navigator.pop(c, (
                              point: LatLng(lat, lng),
                              label: '${r['name'] ?? 'Stop'}'
                            ));
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      debounce?.cancel();
      ctrl.dispose();
    });
    return picked;
  }

  /// Bottom sheet listing the route summary and turn-by-turn steps.
  void _showStepsSheet(
      LatLng dest,
      ({List<LatLng> line, double km, int mins, List<RouteStep> steps}) r,
      [List<({LatLng point, String label})> stops = const []]) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.directions_car, color: Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.km.toStringAsFixed(1)} km · ~${r.mins} min',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('Driving · live traffic',
                            style:
                                TextStyle(color: scheme.outline, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.navigation),
                  label: const Text('Go — live navigation'),
                  onPressed: () {
                    Navigator.pop(context);
                    NavigationScreen.open(
                      context,
                      line: r.line,
                      steps: r.steps,
                      destination: dest,
                      destName: _searchLabel,
                      stops: [for (final s in stops) s.point],
                    );
                  },
                ),
              ),
            ),
            // Stops (waypoints) and an Add-stop control.
            for (var i = 0; i < stops.length; i++)
              ListTile(
                dense: true,
                leading: const Icon(Icons.trip_origin, color: Color(0xFF2563EB)),
                title: Text('Stop ${i + 1}: ${stops[i].label}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove stop',
                  onPressed: () {
                    final next = [...stops]..removeAt(i);
                    Navigator.pop(context);
                    _directionsInApp(dest, stops: next);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Add stop'),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final s = await _pickStop();
                  if (s == null || !mounted) return;
                  nav.pop();
                  _directionsInApp(dest, stops: [...stops, s]);
                },
              ),
            ),
            const Divider(height: 1),
            if (r.steps.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child:
                    Center(child: Text('Turn-by-turn steps unavailable.')),
              )
            else
              for (final s in r.steps)
                ListTile(
                  leading: Icon(_maneuverIcon(s.type, s.modifier),
                      color: scheme.primary),
                  title: Text(
                      s.instruction.isEmpty ? 'Continue' : s.instruction),
                  trailing: Text(_fmtDistance(s.meters),
                      style: TextStyle(color: scheme.outline, fontSize: 12)),
                ),
          ],
        ),
      ),
    );
  }

  IconData _maneuverIcon(String type, String modifier) {
    if (type == 'depart') return Icons.trip_origin;
    if (type == 'arrive') return Icons.flag;
    if (type == 'roundabout' || type == 'rotary') return Icons.rotate_right;
    if (modifier.contains('uturn')) return Icons.u_turn_left;
    if (modifier.contains('left')) return Icons.turn_left;
    if (modifier.contains('right')) return Icons.turn_right;
    return Icons.straight;
  }

  /// Saves the search pin into the user's places (shows on the Saved layer).
  Future<void> _saveSearchPin() async {
    final pin = _searchPin;
    if (pin == null) return;
    try {
      await api.guides.addPlace(
        title: _searchLabel ?? 'Saved spot',
        latitude: pin.latitude,
        longitude: pin.longitude,
      );
      if (mounted) {
        showInfo(context, 'Saved — visible on the Saved layer');
        _loadSaved();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _conversationName(ConversationView c) {
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  /// Sends a place card ("meet me here") into a conversation the user picks.
  Future<void> _sendPlaceToChat({
    required String name,
    String? address,
    required double lat,
    required double lng,
  }) async {
    final convs = await api.messaging
        .conversations()
        .catchError((_) => <ConversationView>[]);
    if (!mounted) return;
    final target = await showModalBottomSheet<ConversationView>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Send place to',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in convs)
                    ListTile(
                      leading: Avatar(
                          url: c.avatar ?? c.otherUser?.picture,
                          name: _conversationName(c)),
                      title: Text(_conversationName(c),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    try {
      await api.messaging.send(
          target.id,
          MessageCreate(
            type: 'place',
            placeName: name,
            placeAddress: address,
            placeLatitude: lat,
            placeLongitude: lng,
          ));
      if (mounted) showInfo(context, 'Sent to chat');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Opens shared reviews for the searched spot. Reviews of unsaved places are
  /// keyed by a coarse geo key (~11 m grid) so everyone who searches the same
  /// spot lands on the same review thread.
  void _reviewSearchPin() {
    final pin = _searchPin;
    if (pin == null) return;
    final key = 'geo:${pin.latitude.toStringAsFixed(4)},'
        '${pin.longitude.toStringAsFixed(4)}';
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlaceReviewsScreen(
        placeKey: key,
        placeName: _searchLabel ?? 'Dropped pin',
        latitude: pin.latitude,
        longitude: pin.longitude,
      ),
    ));
  }

  /// Runs the place search for the current field text. [fromTyping] is a
  /// debounced type-ahead pass (populates results only; never navigates).
  Future<void> _runSearch({bool fromTyping = false}) async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    final coords = _parseCoords(q);
    if (coords != null && !fromTyping) {
      _addRecent(q);
      _dismissSearch();
      setState(() => _center = coords);
      _controller.move(coords, 13);
      _loadAll();
      return;
    }
    final seq = ++_searchSeq;
    if (!fromTyping) setState(() => _searchBusy = true);
    try {
      final r = await geocodePlaces(q, near: _myLocation ?? _center);
      if (!mounted || seq != _searchSeq) return;
      if (r.isEmpty) {
        // Natural-language fallback: "food near me" doesn't geocode, so let the
        // AI clean it to a keyword ("food") and retry once before giving up.
        if (!fromTyping) {
          final cleaned = await _aiCleanQuery(q);
          if (mounted && seq == _searchSeq && cleaned != null && cleaned != q) {
            final r2 = await geocodePlaces(cleaned, near: _myLocation ?? _center);
            if (!mounted || seq != _searchSeq) return;
            if (r2.isNotEmpty) {
              _addRecent(q);
              setState(() =>
                  _searchResults = r2.cast<Map<String, dynamic>>());
              return;
            }
          }
          if (mounted && seq == _searchSeq) {
            showInfo(context, 'No places found for “$q”.');
          }
        }
        setState(() => _searchResults = const []);
      } else if (r.length == 1 && !fromTyping) {
        _addRecent(q);
        _pickSearchResult(r.first.cast<String, dynamic>());
      } else {
        if (!fromTyping) _addRecent(q);
        setState(() => _searchResults = r.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted && seq == _searchSeq && !fromTyping) showError(context, e);
    } finally {
      if (mounted && seq == _searchSeq && !fromTyping) {
        setState(() => _searchBusy = false);
      }
    }
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    if (!_searchActive) setState(() => _searchActive = true);
    if (v.trim().length < 3) {
      setState(() => _searchResults = const []);
      return;
    }
    _searchDebounce = Timer(
        const Duration(milliseconds: 350), () => _runSearch(fromTyping: true));
  }

  /// Closes the search dropdown and drops keyboard focus.
  void _dismissSearch() {
    _searchDebounce?.cancel();
    _searchFocus.unfocus();
    if (mounted) setState(() => _searchActive = false);
  }

  void _pickSearchResult(Map<String, dynamic> r) {
    _dismissSearch();
    _gotoResult(r);
  }

  /// AI-assisted: turn the plain-English field text into a clean place search.
  Future<void> _smartMapSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searchAiBusy = true);
    try {
      final res = await api.maps.aiSearch(q);
      _searchCtrl.text = '${res['search'] ?? q}';
      if (mounted &&
          res['ai'] == true &&
          '${res['summary'] ?? ''}'.isNotEmpty) {
        showInfo(context, 'Searching: ${res['summary']}');
      }
      await _runSearch();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searchAiBusy = false);
    }
  }

  /// Asks the backend AI to turn a plain-English query into a clean place
  /// keyword. Returns null when the AI is off/unavailable (caller falls back).
  Future<String?> _aiCleanQuery(String q) async {
    try {
      final res = await api.maps.aiSearch(q);
      if (res['ai'] != true) return null; // AI not configured — no cleaning
      final s = '${res['search'] ?? ''}'.trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// The results / recents panel shown beneath the top search bar.
  Widget _searchDropdown(ColorScheme scheme) {
    final hasResults = _searchResults.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AI-assisted: turn plain-English text into a clean place search.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: _searchAiBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Smart search'),
                onPressed: _searchAiBusy ? null : _smartMapSearch,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (hasResults)
                  for (final r in _searchResults.take(8)) _searchResultTile(r)
                else ...[
                  if (_recent.isNotEmpty)
                    ListTile(
                      dense: true,
                      title: const Text('Recent',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      trailing: TextButton(
                        onPressed: () {
                          _clearRecents();
                          setState(() {});
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                  for (final q in _recent)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history),
                      title: Text(q),
                      onTap: () {
                        _searchCtrl.text = q;
                        _runSearch();
                      },
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResultTile(Map<String, dynamic> r) {
    final name = '${r['name'] ?? r['display_name'] ?? r['label'] ?? 'Result'}';
    final addr = (r['full_address'] ?? r['display_name'])?.toString();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.place_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (addr != null && addr.isNotEmpty && addr != name)
          ? Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () => _pickSearchResult(r),
    );
  }

  void _toggle(void Function() change) {
    setState(change);
    _savePrefs();
    if (_showSaved && _saved.isEmpty) _loadSaved();
    _loadAll();
  }

  /// All the map controls, reached by long-pressing the search button (the top
  /// bar itself is kept to just the search icon for now).
  void _mapOptionsMenu() {
    ListTile item(IconData icon, String label, VoidCallback onTap,
            {bool active = false}) =>
        ListTile(
          leading: Icon(icon,
              color: active ? Theme.of(context).colorScheme.primary : null),
          title: Text(label),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            item(
                _etaShareId != null ? Icons.share_location : Icons.near_me,
                _etaShareId != null ? 'Stop sharing ETA' : 'Share my ETA',
                _etaShareId != null ? _stopEta : _shareEta,
                active: _etaShareId != null),
            item(Icons.location_searching, 'View a shared ETA', _viewSharedEta),
            const Divider(height: 1),
            item(Icons.straighten, 'Measure distance', _toggleMeasure,
                active: _measuring),
            item(Icons.route, 'Build a route', _toggleRouting,
                active: _routing),
            item(Icons.crop_square, 'Measure area', _toggleArea,
                active: _areaMode),
            const Divider(height: 1),
            item(Icons.layers_outlined, 'Map layers', _layersSheet),
            item(Icons.refresh, 'Search this area', _loadAll),
            item(Icons.tune, 'Search radius', _radiusSheet),
            item(Icons.filter_alt_outlined, 'Filters', _filtersSheet),
            item(Icons.near_me_outlined, 'Nearest to centre', _nearestSheet),
            item(Icons.star_outline, 'Top-rated nearby', _topRatedSheet),
            item(Icons.fit_screen, 'Fit all markers', _fitAll),
            item(Icons.bookmark_outline, 'Saved views', _bookmarksSheet),
            item(Icons.add_location_alt_outlined, 'Save centre as place',
                _savePlaceAtCenter),
            item(Icons.my_location, 'Copy centre coords', _copyCenter),
            item(Icons.settings_outlined, 'Map settings', _settingsSheet),
            item(Icons.info_outline, 'Legend', _legendSheet),
            item(Icons.ios_share, 'Share this location', _shareThisLocation),
            item(Icons.restart_alt, 'Reset all', _resetAll),
          ],
        ),
      ),
    );
  }

  /// Lists the highest-rated places within the search radius of the current
  /// centre; tapping one recentres the map and opens its reviews.
  Future<void> _topRatedSheet() async {
    final center = _controller.camera.center;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => FutureBuilder<List<NearbyRatedPlace>>(
          future: api.guides.nearbyRatedPlaces(
              lat: center.latitude,
              lng: center.longitude,
              radiusKm: _radiusKm),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator()));
            }
            final places = snap.data ?? const <NearbyRatedPlace>[];
            if (places.isEmpty) {
              return const Center(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                          'No rated places within your search radius.')));
            }
            return ListView.builder(
              controller: scroll,
              itemCount: places.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text('Top-rated nearby',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  );
                }
                final p = places[i - 1];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0x33F6C455),
                    child: Text(p.average.toStringAsFixed(1),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF9A7A12))),
                  ),
                  title: Text(p.placeName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('★ ${p.average.toStringAsFixed(1)} · '
                      '${p.count == 1 ? '1 review' : '${p.count} reviews'} · '
                      '${_fmtDistance(p.distanceKm * 1000)} away'),
                  onTap: () {
                    Navigator.pop(context);
                    _controller.move(LatLng(p.latitude, p.longitude), 16);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => PlaceReviewsScreen(
                        placeKey: p.placeKey,
                        placeName: p.placeName,
                        latitude: p.latitude,
                        longitude: p.longitude,
                      ),
                    ));
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Opens the in-app live viewer for a shared ETA from a pasted link or code.
  Future<void> _viewSharedEta() async {
    final input = await promptText(context,
        title: 'View a shared ETA',
        hint: 'Paste the ETA link or code',
        action: 'View');
    if (input == null || input.trim().isEmpty || !mounted) return;
    final trimmed = input.trim();
    // Accept a full okayspace.ca/eta/<id> URL or a bare share code.
    var id = trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      id = uri.pathSegments.last;
    }
    if (id.isEmpty) return;
    EtaViewScreen.open(context, id);
  }

  /// Starts a live ETA share to a searched destination and copies the
  /// public tracking link.
  Future<void> _shareEta() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => const _ShareEtaDialog(),
    );
    if (result == null) return;
    final (destQuery, minutes) = result;
    try {
      double? dLat, dLng;
      String destName = destQuery;
      final places = await geocodePlaces(destQuery, near: _center);
      if (places.isNotEmpty) {
        final r = places.first;
        destName = '${r['name'] ?? r['display_name'] ?? destQuery}';
        final lat = r['lat'] ?? r['latitude'];
        final lng = r['lng'] ?? r['lon'] ?? r['longitude'];
        dLat = lat is num ? lat.toDouble() : double.tryParse('$lat');
        dLng = lng is num ? lng.toDouble() : double.tryParse('$lng');
      }
      final share = await api.roadside.startEta(
        destinationName: destName,
        destinationLatitude: dLat,
        destinationLongitude: dLng,
        initialLatitude: _center.latitude,
        initialLongitude: _center.longitude,
        etaMinutes: minutes,
        ttlMinutes: minutes + 60,
      );
      final shareId = '${share['share_id'] ?? share['id'] ?? ''}';
      if (!mounted) return;
      if (shareId.isEmpty) {
        showInfo(context, 'Could not start the ETA share.');
        return;
      }
      setState(() {
        _etaShareId = shareId;
        _etaDestination = destName;
        _etaDest = (dLat != null && dLng != null) ? LatLng(dLat, dLng) : null;
      });
      // Keep the share live: push the device position as it moves so the
      // recipient sees us actually travelling, not a frozen pin.
      _startEtaUpdates(shareId);
      final url = 'https://okayspace.ca/eta/$shareId';
      Clipboard.setData(ClipboardData(text: url));
      showInfo(context, 'ETA link copied: $url');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Streams GPS fixes to the server for an active ETA share (throttled to one
  /// push per 10s), recomputing the ETA from remaining distance and speed.
  void _startEtaUpdates(String shareId) {
    _etaSub?.cancel();
    _etaSub = fixStream().listen((fix) async {
      if (!mounted || _etaShareId != shareId) return;
      final now = DateTime.now();
      if (now.difference(_lastEtaPush).inSeconds < 10) return;
      _lastEtaPush = now;
      int? mins;
      final dest = _etaDest;
      if (dest != null) {
        final metres = _distance(fix.point, dest);
        // Use live speed when actually moving, else a sane road default.
        final kmh = fix.speedKmh > 5 ? fix.speedKmh : 40.0;
        mins = (metres / 1000 / kmh * 60).round();
      }
      try {
        await api.roadside.updateEta(shareId,
            latitude: fix.point.latitude,
            longitude: fix.point.longitude,
            etaMinutes: mins);
      } on ApiException catch (e) {
        // 410/404 → the share ended or expired server-side; stop locally.
        if (mounted &&
            _etaShareId == shareId &&
            (e.statusCode == 410 || e.statusCode == 404)) {
          await _etaSub?.cancel();
          _etaSub = null;
          if (!mounted) return;
          setState(() {
            _etaShareId = null;
            _etaDestination = null;
            _etaDest = null;
          });
          showInfo(context, 'ETA sharing ended');
        }
      } catch (_) {/* transient — retry on the next fix */}
    });
  }

  /// Re-copies the public tracking link for the active share.
  void _copyEtaLink() {
    final id = _etaShareId;
    if (id == null) return;
    Clipboard.setData(ClipboardData(text: 'https://okayspace.ca/eta/$id'));
    showInfo(context, 'ETA link copied');
  }

  Future<void> _stopEta() async {
    final id = _etaShareId;
    if (id == null) return;
    await _etaSub?.cancel();
    _etaSub = null;
    try {
      await api.roadside.stopEta(id);
    } catch (_) {/* already expired is fine */}
    if (mounted) {
      setState(() {
        _etaShareId = null;
        _etaDestination = null;
        _etaDest = null;
      });
      showInfo(context, 'ETA sharing stopped');
    }
  }

  double? _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// Coerces a dynamic JSON list into a list of string-keyed maps.
  List<Map<String, dynamic>> _mapList(dynamic v) => v is List
      ? v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
      : const [];

  static const _distance = Distance();

  String _fmtDistance(double metres) {
    if (_units == 'mi') {
      final miles = metres / 1609.344;
      return miles >= 0.1
          ? '${miles.toStringAsFixed(1)} mi'
          : '${(metres / 0.3048).round()} ft';
    }
    return metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(1)} km'
        : '${metres.round()} m';
  }

  /// Fits the camera to all currently shown markers.
  void _fitAll() {
    final pts = <LatLng>[
      for (final l in _listings)
        if (l.latitude != null && l.longitude != null)
          LatLng(l.latitude!, l.longitude!),
      for (final r in _roadside) LatLng(r.latitude, r.longitude),
      for (final pl in _saved)
        if (pl.latitude != null && pl.longitude != null)
          LatLng(pl.latitude!, pl.longitude!),
    ];
    if (pts.isEmpty) {
      showInfo(context, 'Nothing to fit yet');
      return;
    }
    _controller.fitCamera(CameraFit.coordinates(
        coordinates: pts, padding: const EdgeInsets.all(60)));
  }

  void _copyCenter() {
    final c = _controller.camera.center;
    Clipboard.setData(
        ClipboardData(text: '${c.latitude}, ${c.longitude}'));
    showInfo(context, 'Centre coordinates copied');
  }

  Future<void> _savePlaceAtCenter() => _savePlaceAt(_controller.camera.center);

  void _resetAll() {
    setState(() {
      _showListings = true;
      _showRoadside = false;
      _showTransit = false;
      _showSaved = false;
      _showRated = false;
      _maxPrice = 0;
      _minPrice = 0;
      _withPhotosOnly = false;
      _roadsideStatus = 'all';
      _savedCategory = 'all';
      _radiusKm = 25;
    });
    _savePrefs();
    _loadAll();
    showInfo(context, 'Filters and layers reset');
  }

  // --- Directions / routing -----------------------------------------------

  /// Sets a straight-line directions target from the user's location pin.
  void _directionsToPoint(LatLng to) {
    if (_myLocation == null) {
      showInfo(context, 'Set your location pin first (long-press the map)');
      return;
    }
    setState(() => _directionsTo = to);
    final m = _distance(_myLocation!, to);
    final bearing = _distance.bearing(_myLocation!, to);
    showInfo(context,
        '${_fmtDistance(m)} · ${_compassPoint(bearing)} (${bearing.round()}°)');
  }

  String _compassPoint(double bearing) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final b = (bearing % 360 + 360) % 360;
    return dirs[((b + 22.5) ~/ 45) % 8];
  }

  void _toggleRouting() {
    setState(() {
      _routing = !_routing;
      _route.clear();
      if (_routing) {
        _measuring = false;
        _areaMode = false;
      }
    });
    if (_routing) showInfo(context, 'Tap stops to build a route');
  }

  double get _routeTotal {
    var t = 0.0;
    for (var i = 1; i < _route.length; i++) {
      t += _distance(_route[i - 1], _route[i]);
    }
    return t;
  }

  // --- Area measure --------------------------------------------------------

  void _toggleArea() {
    setState(() {
      _areaMode = !_areaMode;
      _areaPoints.clear();
      if (_areaMode) {
        _measuring = false;
        _routing = false;
      }
    });
    if (_areaMode) showInfo(context, 'Tap 3+ points to measure an area');
  }

  /// Shoelace area (m²) for the tapped polygon, using an equirectangular
  /// projection around the polygon's mean latitude — fine for small areas.
  double get _areaValue {
    if (_areaPoints.length < 3) return 0;
    const r = 6378137.0; // earth radius (m)
    final meanLat = _areaPoints
            .map((p) => p.latitude)
            .reduce((a, b) => a + b) /
        _areaPoints.length;
    final cosLat = math.cos(meanLat * math.pi / 180);
    double sum = 0;
    for (var i = 0; i < _areaPoints.length; i++) {
      final a = _areaPoints[i];
      final b = _areaPoints[(i + 1) % _areaPoints.length];
      final ax = a.longitude * math.pi / 180 * r * cosLat;
      final ay = a.latitude * math.pi / 180 * r;
      final bx = b.longitude * math.pi / 180 * r * cosLat;
      final by = b.latitude * math.pi / 180 * r;
      sum += (ax * by - bx * ay);
    }
    return sum.abs() / 2;
  }

  String _fmtArea(double m2) {
    if (_units == 'mi') {
      final acres = m2 / 4046.86;
      return acres >= 1
          ? '${acres.toStringAsFixed(2)} acres'
          : '${(m2 * 10.7639).round()} ft²';
    }
    return m2 >= 10000
        ? '${(m2 / 1e6).toStringAsFixed(2)} km²'
        : '${m2.round()} m²';
  }

  // --- Bookmarks -----------------------------------------------------------

  Future<void> _addBookmark() async {
    final name = await promptText(context,
        title: 'Save this view', action: 'Save');
    if (name == null || name.trim().isEmpty) return;
    final c = _controller.camera;
    setState(() => _bookmarks = [
          ..._bookmarks,
          {
            'name': name.trim(),
            'lat': c.center.latitude,
            'lng': c.center.longitude,
            'zoom': c.zoom,
          }
        ]);
    _storage.write(key: _bookmarksKey, value: jsonEncode(_bookmarks)).ignore();
    if (mounted) showInfo(context, 'View saved');
  }

  void _removeBookmark(int i) {
    setState(() => _bookmarks = [..._bookmarks]..removeAt(i));
    _storage.write(key: _bookmarksKey, value: jsonEncode(_bookmarks)).ignore();
  }

  void _bookmarksSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Saved views',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Save current'),
                onPressed: () {
                  Navigator.pop(context);
                  _addBookmark();
                },
              ),
            ),
            if (_bookmarks.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No saved views yet.')),
            for (var i = 0; i < _bookmarks.length; i++)
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text('${_bookmarks[i]['name']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeBookmark(i),
                ),
                onTap: () {
                  final b = _bookmarks[i];
                  Navigator.pop(context);
                  setState(() => _center = LatLng(
                      (b['lat'] as num).toDouble(),
                      (b['lng'] as num).toDouble()));
                  _controller.move(_center, (b['zoom'] as num).toDouble());
                  _loadAll();
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- My location / identify / save place --------------------------------

  void _setMyLocation(LatLng p) {
    setState(() => _myLocation = p);
    _storage
        .write(
            key: _myLocKey,
            value: jsonEncode({'lat': p.latitude, 'lng': p.longitude}))
        .ignore();
    if (mounted) showInfo(context, 'Location pin set');
  }

  Future<void> _onLongPress(LatLng p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions),
              title: const Text('Directions to here'),
              subtitle: const Text('Route + turn-by-turn steps in the app'),
              onTap: () => Navigator.pop(context, 'directions'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Save as a place'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Set as my location'),
              onTap: () => Navigator.pop(context, 'mylocation'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text("What's here?"),
              onTap: () => Navigator.pop(context, 'identify'),
            ),
          ],
        ),
      ),
    );
    if (action == 'directions') {
      _directionsInApp(p);
    } else if (action == 'mylocation') {
      _setMyLocation(p);
    } else if (action == 'identify') {
      _identifyAt(p);
    } else if (action == 'save') {
      _savePlaceAt(p);
    }
  }

  Future<void> _savePlaceAt(LatLng p) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _SavePlaceDialog(),
    );
    if (result == null) return;
    final (title, category) = result;
    try {
      await api.guides.addPlace(
          title: title,
          category: category,
          latitude: p.latitude,
          longitude: p.longitude);
      if (!mounted) return;
      showInfo(context, 'Place saved');
      if (_showSaved) _loadSaved();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _identifyAt(LatLng p) {
    setState(() => _identify = p);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(
              '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
          subtitle: Text(_myLocation == null
              ? 'Long-press elsewhere to compare'
              : '${_fmtDistance(_distance(p, _myLocation!))} from your pin'),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: '${p.latitude}, ${p.longitude}'));
              Navigator.pop(context);
              showInfo(context, 'Coordinates copied');
            },
          ),
        ),
      ),
    );
  }

  // --- Distance-measure tool ----------------------------------------------

  void _toggleMeasure() {
    setState(() {
      _measuring = !_measuring;
      _measurePoints.clear();
    });
    if (_measuring) {
      showInfo(context, 'Tap two or more points to measure');
    }
  }

  double get _measureTotal {
    var total = 0.0;
    for (var i = 1; i < _measurePoints.length; i++) {
      total += _distance(_measurePoints[i - 1], _measurePoints[i]);
    }
    return total;
  }

  void _onTap(LatLng p) {
    // A tap on the map first closes the search dropdown.
    if (_searchActive) {
      _dismissSearch();
      return;
    }
    if (_measuring) {
      setState(() => _measurePoints.add(p));
    } else if (_routing) {
      setState(() => _route.add(p));
    } else if (_areaMode) {
      setState(() => _areaPoints.add(p));
    }
  }

  // --- External maps / share ----------------------------------------------

  /// Opens turn-by-turn directions to [p] in the device's maps app (Google
  /// Maps web/app — it fills in the current location as the origin, or we pass
  /// our known pin). Falls back to copying the link if nothing can handle it.
  Future<void> _openExternal(LatLng p) async {
    final origin = _myLocation != null
        ? '&origin=${_myLocation!.latitude},${_myLocation!.longitude}'
        : '';
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1$origin'
        '&destination=${p.latitude},${p.longitude}');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {/* fall through to copy */}
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (mounted) showInfo(context, 'Directions link copied');
  }

  void _shareThisLocation() {
    final c = _controller.camera.center;
    final url =
        'https://www.google.com/maps/search/?api=1&query=${c.latitude},${c.longitude}';
    Clipboard.setData(ClipboardData(text: url));
    showInfo(context, 'Location link copied');
  }

  // --- Nearest list --------------------------------------------------------

  void _nearestSheet() {
    // (distance, title, subtitle, point, price)
    final items = <(double, String, String, LatLng, double)>[];
    for (final l in _listings) {
      if (l.latitude != null && l.longitude != null) {
        final pt = LatLng(l.latitude!, l.longitude!);
        items.add((_distance(_center, pt), l.title,
            '${l.currency} ${l.price.toStringAsFixed(0)}', pt,
            l.price.toDouble()));
      }
    }
    for (final r in _roadside) {
      final pt = LatLng(r.latitude, r.longitude);
      items.add((_distance(_center, pt), r.service, r.status, pt, -1.0));
    }
    void sortItems() {
      switch (_nearestSort) {
        case 'price':
          items.sort((a, b) => a.$5.compareTo(b.$5));
        case 'name':
          items.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
        default:
          items.sort((a, b) => a.$1.compareTo(b.$1));
      }
    }

    sortItems();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (c, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          builder: (_, ctrl) => ListView(
            controller: ctrl,
            children: [
              ListTile(
                title: const Text('Nearest to centre',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'distance', icon: Icon(Icons.straighten, size: 16)),
                    ButtonSegment(value: 'price', icon: Icon(Icons.sell_outlined, size: 16)),
                    ButtonSegment(value: 'name', icon: Icon(Icons.sort_by_alpha, size: 16)),
                  ],
                  selected: {_nearestSort},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _nearestSort = s.first);
                    setSheet(sortItems);
                  },
                ),
              ),
              if (items.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nothing on the map yet.')),
              for (final it in items)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(it.$2),
                  subtitle: Text(it.$3),
                  trailing: Text(_fmtDistance(it.$1)),
                  onTap: () {
                    Navigator.pop(context);
                    _controller.move(it.$4, 14);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Legend + settings ---------------------------------------------------

  void _legendSheet() {
    Widget row(Color c, IconData i, String label) => ListTile(
          dense: true,
          leading: Icon(i, color: c),
          title: Text(label),
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Legend',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            row(Theme.of(context).colorScheme.primary, Icons.location_on,
                'Marketplace listing'),
            row(const Color(0xFFF59E0B), Icons.car_repair, 'Roadside request'),
            row(const Color(0xFF6366F1), Icons.directions_transit,
                'Transit stop'),
            row(const Color(0xFF10B981), Icons.bookmark, 'Saved place'),
            row(const Color(0xFFF6C455), Icons.star, 'Top-rated place'),
            row(const Color(0xFF2563EB), Icons.my_location, 'Your location pin'),
          ],
        ),
      ),
    );
  }

  void _settingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (c, setSheet) {
          void apply(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
            _savePrefs();
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                    title: Text('Map settings',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final s in _styles)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: _tileStyle == s.id,
                          onSelected: (_) => apply(() => _tileStyle = s.id),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Show radius circle'),
                  value: _showRadiusCircle,
                  onChanged: (v) => apply(() => _showRadiusCircle = v),
                ),
                SwitchListTile(
                  title: const Text('Centre crosshair'),
                  value: _showCrosshair,
                  onChanged: (v) => apply(() => _showCrosshair = v),
                ),
                SwitchListTile(
                  title: const Text('Cluster nearby markers'),
                  value: _cluster,
                  onChanged: (v) => apply(() => _cluster = v),
                ),
                SwitchListTile(
                  title: const Text('Lat/long grid'),
                  value: _showGrid,
                  onChanged: (v) => apply(() => _showGrid = v),
                ),
                SwitchListTile(
                  title: const Text('Marker labels'),
                  value: _showLabels,
                  onChanged: (v) => apply(() => _showLabels = v),
                ),
                SwitchListTile(
                  title: const Text('Lock rotation (north up)'),
                  value: _rotationLocked,
                  onChanged: (v) => apply(() {
                    _rotationLocked = v;
                    if (v && _mapReady) _controller.rotate(0);
                  }),
                ),
                SwitchListTile(
                  title: const Text('Search as I move the map'),
                  value: _searchAsIMove,
                  onChanged: (v) => setSheet(() {
                    setState(() => _searchAsIMove = v);
                  }),
                ),
                ListTile(
                  title: const Text('Units'),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'km', label: Text('km')),
                      ButtonSegment(value: 'mi', label: Text('mi')),
                    ],
                    selected: {_units},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => apply(() => _units = s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Pin size'),
                      Expanded(
                        child: Slider(
                          value: _pinSize,
                          min: 28,
                          max: 52,
                          onChanged: (v) => apply(() => _pinSize = v),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Reset layers & filters'),
                  onTap: () {
                    Navigator.pop(context);
                    _resetAll();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Filters -------------------------------------------------------------

  void _filtersSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filters',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_minPrice == 0
                    ? 'Min listing price: any'
                    : 'Min listing price: \$${_minPrice.round()}'),
                Slider(
                  value: _minPrice,
                  min: 0,
                  max: 5000,
                  divisions: 50,
                  label: _minPrice == 0 ? 'Any' : '\$${_minPrice.round()}',
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _minPrice = v);
                  },
                ),
                Text(_maxPrice == 0
                    ? 'Max listing price: any'
                    : 'Max listing price: \$${_maxPrice.round()}'),
                Slider(
                  value: _maxPrice,
                  min: 0,
                  max: 5000,
                  divisions: 50,
                  label: _maxPrice == 0 ? 'Any' : '\$${_maxPrice.round()}',
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _maxPrice = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Listings with photos only'),
                  value: _withPhotosOnly,
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _withPhotosOnly = v);
                  },
                ),
                const SizedBox(height: 8),
                const Text('Roadside status'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in const ['all', 'open', 'active'])
                      ChoiceChip(
                        label: Text(s[0].toUpperCase() + s.substring(1)),
                        selected: _roadsideStatus == s,
                        onSelected: (_) {
                          setSheet(() {});
                          setState(() => _roadsideStatus = s);
                        },
                      ),
                  ],
                ),
                if (_savedCategories.length > 1) ...[
                  const SizedBox(height: 8),
                  const Text('Saved place category'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final cat in _savedCategories)
                        ChoiceChip(
                          label: Text(cat == 'all' ? 'All' : cat),
                          selected: _savedCategory == cat,
                          onSelected: (_) {
                            setSheet(() {});
                            setState(() => _savedCategory = cat);
                          },
                        ),
                    ],
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Groups [markers] into coarse grid cells when clustering is on.
  List<Marker> _clusterMarkers(List<Marker> markers) {
    if (!_cluster || markers.length < 12) return markers;
    final zoom = _liveZoom;
    final cell = 0.6 / (zoom <= 0 ? 1 : zoom); // degrees per cluster cell
    final buckets = <String, List<Marker>>{};
    for (final m in markers) {
      final key =
          '${(m.point.latitude / cell).floor()}:${(m.point.longitude / cell).floor()}';
      buckets.putIfAbsent(key, () => []).add(m);
    }
    final out = <Marker>[];
    for (final group in buckets.values) {
      if (group.length == 1) {
        out.add(group.first);
        continue;
      }
      var lat = 0.0, lng = 0.0;
      for (final m in group) {
        lat += m.point.latitude;
        lng += m.point.longitude;
      }
      final center = LatLng(lat / group.length, lng / group.length);
      out.add(Marker(
        point: center,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _controller.move(center, _controller.camera.zoom + 2),
          child: Container(
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('${group.length}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Mapbox is the sole provider: without the build-time token there is
    // nothing to render — say so instead of showing a gray map.
    if (!_hasMapbox) {
      return Scaffold(
        extendBody: !widget.embedded,
        bottomNavigationBar: widget.embedded ? null : const OkayBottomNav(),
        body: const CenteredMessage(
            message:
                'Maps are powered by Mapbox.\nThis build is missing the MAPBOX_TOKEN — add the secret and redeploy.',
            icon: Icons.map_outlined),
      );
    }

    final markers = <Marker>[
      if (_showListings)
        for (final l in _listings)
          if (l.latitude != null &&
              l.longitude != null &&
              (_maxPrice == 0 || l.price <= _maxPrice) &&
              l.price >= _minPrice &&
              (!_withPhotosOnly || l.photos.isNotEmpty))
            _marker(LatLng(l.latitude!, l.longitude!), Icons.location_on,
                scheme.primary, () => _showListing(l),
                label: l.title),
      if (_showRoadside)
        for (final r in _roadside)
          if (_roadsideStatus == 'all' ||
              r.status.toLowerCase() == _roadsideStatus)
            ...[
              _marker(LatLng(r.latitude, r.longitude), Icons.car_repair,
                  const Color(0xFFF59E0B), () => _showRoadsideReq(r),
                  label: r.service),
              // Tow drop-off, flagged and linked to the pickup (line below).
              if (r.destLatitude != null && r.destLongitude != null)
                _marker(
                    LatLng(r.destLatitude!, r.destLongitude!),
                    Icons.flag,
                    const Color(0xFFF59E0B),
                    () => _showRoadsideReq(r),
                    label: r.destName ?? 'Drop-off'),
            ],
      if (_showTransit)
        for (final t in _transit)
          if (_num(t['lat'] ?? t['latitude']) != null &&
              _num(t['lon'] ?? t['lng'] ?? t['longitude']) != null)
            _marker(
                LatLng(_num(t['lat'] ?? t['latitude'])!,
                    _num(t['lon'] ?? t['lng'] ?? t['longitude'])!),
                Icons.directions_transit,
                const Color(0xFF6366F1),
                () => _showTransitStop(t),
                label: '${t['name'] ?? t['stop_name'] ?? ''}'),
      if (_showSaved)
        for (final pl in _saved)
          if (pl.latitude != null &&
              pl.longitude != null &&
              (_savedCategory == 'all' || pl.category == _savedCategory))
            _marker(LatLng(pl.latitude!, pl.longitude!), Icons.bookmark,
                const Color(0xFF10B981), () => _showSavedPlace(pl),
                label: pl.title),
      if (_showRated)
        for (final p in _rated)
          _marker(LatLng(p.latitude, p.longitude), Icons.star,
              const Color(0xFFF6C455), () => _showRatedPlace(p),
              label: '${p.placeName} ★${p.average.toStringAsFixed(1)}'),
    ];

    if (_searchPin != null) {
      markers.add(Marker(
        point: _searchPin!,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: const Icon(Icons.location_pin,
            color: Color(0xFFEF4444), size: 40),
      ));
    }

    final shownMarkers = _clusterMarkers(markers);
    final radiusMetres = _radiusKm * 1000;

    return Scaffold(
      extendBody: !widget.embedded,
      bottomNavigationBar: widget.embedded ? null : const OkayBottomNav(),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 11,
              interactionOptions: InteractionOptions(
                flags: _rotationLocked
                    ? InteractiveFlag.all & ~InteractiveFlag.rotate
                    : InteractiveFlag.all,
              ),
              onMapReady: () {
                _mapReady = true;
                if (_restoreZoom != null) {
                  _controller.move(_center, _restoreZoom!);
                  _restoreZoom = null;
                }
                setState(() => _liveZoom = _controller.camera.zoom);
              },
              onTap: (_, point) => _onTap(point),
              onLongPress: (_, point) => _onLongPress(point),
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
                _liveZoom = camera.zoom;
                if (hasGesture) {
                  _onMapGesture();
                  if (_searchAsIMove) _loadAll();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _style.tileUrl,
                userAgentPackageName: 'ca.okayspace.app',
                tileSize: 512,
                zoomOffset: -1,
                additionalOptions: {'token': _mapboxToken},
                errorTileCallback: (tile, error, stackTrace) => _onTileError(),
              ),
              if (_showGrid) PolylineLayer(polylines: _graticule()),
              if (_showRadiusCircle)
                CircleLayer(circles: [
                  CircleMarker(
                    point: _center,
                    radius: radiusMetres,
                    useRadiusInMeter: true,
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderColor: scheme.primary.withValues(alpha: 0.5),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              if (_areaMode && _areaPoints.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(
                    points: _areaPoints,
                    color: scheme.tertiary.withValues(alpha: 0.2),
                    borderColor: scheme.tertiary,
                    borderStrokeWidth: 2,
                  ),
                ]),
              if (_measuring && _measurePoints.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _measurePoints,
                    strokeWidth: 3,
                    color: scheme.tertiary,
                  ),
                ]),
              if (_routing && _route.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _route,
                    strokeWidth: 4,
                    color: scheme.primary,
                  ),
                ]),
              if (_directionsTo != null && _myLocation != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [_myLocation!, _directionsTo!],
                    strokeWidth: 3,
                    color: const Color(0xFF2563EB),
                  ),
                ]),
              if (_roadRoute.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _roadRoute,
                    strokeWidth: 6,
                    color: const Color(0xFF3B82F6),
                    borderStrokeWidth: 2.5,
                    borderColor: const Color(0xFF1E3A8A),
                  ),
                ]),
              // Tow pickup → drop-off connectors.
              if (_showRoadside)
                PolylineLayer(polylines: [
                  for (final r in _roadside)
                    if (r.destLatitude != null &&
                        r.destLongitude != null &&
                        (_roadsideStatus == 'all' ||
                            r.status.toLowerCase() == _roadsideStatus))
                      Polyline(
                        points: [
                          LatLng(r.latitude, r.longitude),
                          LatLng(r.destLatitude!, r.destLongitude!),
                        ],
                        strokeWidth: 2,
                        color: const Color(0xFFF59E0B),
                      ),
                ]),
              // GPS accuracy ring under the location dot (Apple Maps style).
              if (_myLocation != null && _gpsAccuracyM > 10)
                CircleLayer(circles: [
                  CircleMarker(
                    point: _myLocation!,
                    radius: _gpsAccuracyM,
                    useRadiusInMeter: true,
                    color: const Color(0xFF2563EB).withValues(alpha: 0.10),
                    borderColor:
                        const Color(0xFF2563EB).withValues(alpha: 0.3),
                    borderStrokeWidth: 1,
                  ),
                ]),
              MarkerLayer(markers: [
                ...shownMarkers,
                if (_myLocation != null)
                  Marker(
                    point: _myLocation!,
                    width: 30,
                    height: 30,
                    child: _gpsHeading > 0
                        // Heading known: a rotating direction cone.
                        ? Transform.rotate(
                            angle: _gpsHeading * math.pi / 180,
                            child: const Icon(Icons.navigation,
                                color: Color(0xFF2563EB), size: 26),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF2563EB),
                              border:
                                  Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26, blurRadius: 6),
                              ],
                            ),
                          ),
                  ),
                if (_identify != null)
                  _marker(_identify!, Icons.place, const Color(0xFFEF4444),
                      () => _identifyAt(_identify!)),
                for (final p in _measurePoints)
                  _dot(p, scheme.tertiary),
                for (final p in _route) _dot(p, scheme.primary),
                for (final p in _areaPoints) _dot(p, scheme.tertiary),
              ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© Mapbox © OpenStreetMap'),
                ],
              ),
            ],
          ),

          if (_showCrosshair)
            const IgnorePointer(
                child: Center(
                    child: Icon(Icons.add, size: 30, color: Colors.black54))),

          // Pinned top search bar — type directly here; results drop down just
          // below it (no bottom sheet). Stays put (no hide-on-pan).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                              _searchActive ? Icons.arrow_back : Icons.menu),
                          tooltip: _searchActive ? 'Close search' : 'Menu',
                          onPressed: _searchActive
                              ? () {
                                  _searchCtrl.clear();
                                  _dismissSearch();
                                  setState(() => _searchResults = const []);
                                }
                              : () => openSidebar(context),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: (_) => _runSearch(),
                            onTap: () =>
                                setState(() => _searchActive = true),
                            decoration: const InputDecoration(
                              hintText: 'Search Maps',
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                        if (_searchBusy)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          )
                        else if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchResults = const []);
                            },
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.tune),
                            tooltip: 'Map options & layers',
                            onPressed: _mapOptionsMenu,
                          ),
                      ],
                    ),
                  ),
                  if (_searchActive &&
                      (_searchResults.isNotEmpty ||
                          _recent.isNotEmpty ||
                          _searchCtrl.text.isNotEmpty))
                    _searchDropdown(scheme),
                ],
              ),
            ),
          ),

          if (_loading)
            Positioned(
              top: 116,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('Updating…',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ),
            ),

          // Active ETA-share banner.
          if (_etaShareId != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 64,
              child: Material(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.share_location,
                          color: scheme.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            'Sharing ETA to ${_etaDestination ?? 'destination'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy link',
                        color: scheme.onPrimaryContainer,
                        onPressed: _copyEtaLink,
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        tooltip: "Preview recipient's view",
                        color: scheme.onPrimaryContainer,
                        onPressed: () =>
                            EtaViewScreen.open(context, _etaShareId!),
                      ),
                      TextButton(
                        onPressed: _stopEta,
                        child: const Text('Stop'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Measure read-out banner.
          if (_measuring)
            Positioned(
              left: 12,
              right: 12,
              top: 110,
              child: Material(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.straighten,
                          color: scheme.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            _measurePoints.length < 2
                                ? 'Tap points to measure distance'
                                : 'Distance: ${_fmtDistance(_measureTotal)}',
                            style: TextStyle(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (_measurePoints.isNotEmpty)
                        TextButton(
                            onPressed: () =>
                                setState(_measurePoints.clear),
                            child: const Text('Clear')),
                    ],
                  ),
                ),
              ),
            ),

          // Route banner.
          if (_routing)
            Positioned(
              left: 12,
              right: 12,
              top: 110,
              child: _toolBanner(
                  Icons.route,
                  _route.length < 2
                      ? 'Tap stops to build a route'
                      : '${_route.length} stops · ${_fmtDistance(_routeTotal)}',
                  onClear: _route.isEmpty ? null : () => setState(_route.clear)),
            ),
          // Area banner.
          if (_areaMode)
            Positioned(
              left: 12,
              right: 12,
              top: 110,
              child: _toolBanner(
                  Icons.crop_square,
                  _areaPoints.length < 3
                      ? 'Tap 3+ points to measure area'
                      : 'Area: ${_fmtArea(_areaValue)}',
                  onClear: _areaPoints.isEmpty
                      ? null
                      : () => setState(_areaPoints.clear)),
            ),

          // GPS recenter button — sits low (just above the nav), and lifts above
          // the search-result card when one is showing.
          Positioned(
            right: 12,
            bottom: _searchPin != null
                ? (widget.embedded ? 160 : 170)
                : (widget.embedded ? 100 : 108),
            child: FloatingActionButton.small(
              heroTag: 'locate-me',
              onPressed: _locating ? null : _recenterOnMe,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
          // Live speed chip while moving (Apple Maps drive style).
          if (_gpsSpeedKmh > 1)
            Positioned(
              left: 12,
              top: 100,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
                child: Text('${_gpsSpeedKmh.round()} km/h',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          // Drive-route chip for the multi-stop route builder.
          if (_routing && _route.length >= 2)
            Positioned(
              left: 12,
              bottom: widget.embedded ? 160 : 170,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.route, size: 18),
                label: Text('Drive route (${_route.length} stops)'),
                onPressed: () => _fetchDriveRoute(List.of(_route)),
              ),
            ),
          // Search result card: name + real directions hand-off.
          if (_searchPin != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: widget.embedded ? 90 : 100,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_searchLabel ?? 'Search result',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                if (_searchAddress != null) ...[
                                  const SizedBox(height: 2),
                                  Text(_searchAddress!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline)),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                    _routeSummary ??
                                        (_myLocation != null
                                            ? '${_fmtDistance(_distance(_myLocation!, _searchPin!))} away'
                                            : 'Tap Directions to route here'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _routeSummary != null
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: _routeSummary != null
                                            ? const Color(0xFF2563EB)
                                            : Theme.of(context)
                                                .colorScheme
                                                .outline)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() {
                              _searchPin = null;
                              _searchLabel = null;
                              _searchAddress = null;
                              _roadRoute = const [];
                              _routeSummary = null;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Primary call-to-action: big blue Directions button.
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12)),
                          icon: const Icon(Icons.directions),
                          label: const Text('Directions'),
                          onPressed: () => _directionsInApp(_searchPin!),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Secondary actions.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Send'),
                            onPressed: () => _sendPlaceToChat(
                              name: _searchLabel ?? 'Dropped pin',
                              lat: _searchPin!.latitude,
                              lng: _searchPin!.longitude,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Reviews'),
                            onPressed: _reviewSearchPin,
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.bookmark_add_outlined,
                                size: 18),
                            label: const Text('Save'),
                            onPressed: _saveSearchPin,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolBanner(IconData icon, String text, {VoidCallback? onClear}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: scheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600)),
            ),
            if (onClear != null)
              TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
      ),
    );
  }

  void _showSavedPlace(Place pl) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x3310B981),
                child: Icon(Icons.bookmark, color: Color(0xFF10B981)),
              ),
              title: Text(pl.title),
              subtitle: Text([
                if (pl.address != null) pl.address!,
                if (pl.category != null) pl.category!,
                if (pl.latitude != null && pl.longitude != null)
                  '${_fmtDistance(_distance(_center, LatLng(pl.latitude!, pl.longitude!)))} from centre',
              ].join(' · ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pl.latitude != null && pl.longitude != null)
                    IconButton(
                      icon: const Icon(Icons.near_me_outlined),
                      tooltip: 'Directions from my pin',
                      onPressed: () {
                        Navigator.pop(context);
                        _directionsToPoint(LatLng(pl.latitude!, pl.longitude!));
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.directions_outlined),
                    tooltip: 'Open in Maps',
                    onPressed: pl.latitude != null && pl.longitude != null
                        ? () {
                            Navigator.pop(context);
                            _openExternal(LatLng(pl.latitude!, pl.longitude!));
                          }
                        : null,
                  ),
                ],
              ),
            ),
            _PlaceReviewsTile(
              placeKey: pl.id,
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PlaceReviewsScreen(
                    placeKey: pl.id,
                    placeName: pl.title,
                    latitude: pl.latitude,
                    longitude: pl.longitude,
                  ),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('Add to guide'),
              onTap: () {
                Navigator.pop(context);
                _addPlaceToGuide(pl);
              },
            ),
            if (pl.latitude != null && pl.longitude != null)
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Send to chat'),
                onTap: () {
                  Navigator.pop(context);
                  _sendPlaceToChat(
                    name: pl.title,
                    address: pl.address,
                    lat: pl.latitude!,
                    lng: pl.longitude!,
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Remove place',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteSavedPlace(pl);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Adds a saved place to one of the user's guides (picked from a sheet).
  Future<void> _addPlaceToGuide(Place pl) async {
    final guides =
        await api.guides.guides().catchError((_) => <Guide>[]);
    if (!mounted) return;
    if (guides.isEmpty) {
      showInfo(context, 'Create a guide first from the Guides screen');
      return;
    }
    final guide = await showModalBottomSheet<Guide>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Add to guide',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in guides)
                    ListTile(
                      leading:
                          const Icon(Icons.collections_bookmark_outlined),
                      title: Text(g.name),
                      onTap: () => Navigator.pop(context, g),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (guide == null || !mounted) return;
    try {
      await api.guides.addToGuide(guide.id, pl.id);
      if (mounted) showInfo(context, 'Added to ${guide.name}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _showRatedPlace(NearbyRatedPlace p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x33F6C455),
            child: Icon(Icons.star, color: Color(0xFFF6C455)),
          ),
          title: Text(p.placeName),
          subtitle: Text('★ ${p.average.toStringAsFixed(1)} · '
              '${p.count == 1 ? '1 review' : '${p.count} reviews'} · '
              '${_fmtDistance(p.distanceKm * 1000)} away'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PlaceReviewsScreen(
                placeKey: p.placeKey,
                placeName: p.placeName,
                latitude: p.latitude,
                longitude: p.longitude,
              ),
            ));
          },
        ),
      ),
    );
  }

  Future<void> _deleteSavedPlace(Place pl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove place?'),
        content: Text('Remove "${pl.title}" from your saved places?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.guides.deletePlace(pl.id);
      if (!mounted) return;
      setState(() => _saved = _saved.where((p) => p.id != pl.id).toList());
      showInfo(context, 'Place removed');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Marker _dot(LatLng p, Color color) => Marker(
        point: p,
        width: 16,
        height: 16,
        child: Container(
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2))),
      );

  /// Builds a lat/long graticule across the current visible bounds.
  List<Polyline> _graticule() {
    if (!_mapReady) return const [];
    final cam = _controller.camera;
    final b = cam.visibleBounds;
    // Choose a spacing that yields a handful of lines for the current span.
    final span = (b.north - b.south).abs();
    double step = 1;
    for (final s in const [10.0, 5.0, 2.0, 1.0, 0.5, 0.25, 0.1, 0.05, 0.01]) {
      if (span / s >= 4) {
        step = s;
        break;
      }
      step = s;
    }
    final lines = <Polyline>[];
    final color = (_style.dark ? Colors.white : Colors.black).withValues(alpha: 0.18);
    for (var lat = (b.south / step).ceil() * step;
        lat <= b.north;
        lat += step) {
      lines.add(Polyline(
          points: [LatLng(lat, b.west), LatLng(lat, b.east)],
          strokeWidth: 0.5,
          color: color));
    }
    for (var lng = (b.west / step).ceil() * step;
        lng <= b.east;
        lng += step) {
      lines.add(Polyline(
          points: [LatLng(b.south, lng), LatLng(b.north, lng)],
          strokeWidth: 0.5,
          color: color));
    }
    return lines;
  }

  Marker _marker(LatLng point, IconData icon, Color color, VoidCallback onTap,
      {String? label}) {
    final showLabel = _showLabels && label != null && label.isNotEmpty;
    return Marker(
      point: point,
      width: showLabel ? 120 : _pinSize + 6,
      height: _pinSize + (showLabel ? 18 : 6),
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: _pinSize, shadows: const [
              Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
            ]),
            if (showLabel)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }

  /// Toggle which marker layers show on the map (moved here from the search
  /// panel).
  void _layersSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Map layers',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _layerChip('Listings', Icons.storefront, _showListings, () {
                      _toggle(() => _showListings = !_showListings);
                      setS(() {});
                    }),
                    _layerChip('Roadside', Icons.car_repair, _showRoadside, () {
                      _toggle(() => _showRoadside = !_showRoadside);
                      setS(() {});
                    }),
                    _layerChip(
                        'Transit', Icons.directions_transit, _showTransit, () {
                      _toggle(() => _showTransit = !_showTransit);
                      setS(() {});
                    }),
                    _layerChip('Saved', Icons.bookmark, _showSaved, () {
                      _toggle(() => _showSaved = !_showSaved);
                      setS(() {});
                    }),
                    _layerChip('Rated', Icons.star, _showRated, () {
                      _toggle(() => _showRated = !_showRated);
                      setS(() {});
                    }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _layerChip(
      String label, IconData icon, bool selected, VoidCallback onTap) {
    return FilterChip(
      avatar: Icon(icon,
          size: 16,
          color: selected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.primary),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Future<void> _radiusSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Search radius: ${_radiusKm.round()} km',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final km in const [5.0, 10.0, 25.0, 50.0, 100.0])
                      ChoiceChip(
                        label: Text('${km.round()} km'),
                        selected: _radiusKm == km,
                        onSelected: (_) {
                          setSheet(() => _radiusKm = km);
                          setState(() {});
                        },
                      ),
                  ],
                ),
                Slider(
                  value: _radiusKm,
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${_radiusKm.round()} km',
                  onChanged: (v) {
                    setSheet(() => _radiusKm = v);
                    setState(() {});
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () {
                      Navigator.pop(context);
                      _savePrefs();
                      _loadAll();
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showListing(Listing l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: l.photos.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(l.photos.first,
                      width: 52, height: 52, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 52, height: 52)))
              : const Icon(Icons.shopping_bag_outlined),
          title: Text(l.title),
          subtitle: Text([
            '${l.currency} ${l.price.toStringAsFixed(2)}',
            if (l.latitude != null && l.longitude != null)
              '${_fmtDistance(_distance(_center, LatLng(l.latitude!, l.longitude!)))} from centre',
          ].join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (l.latitude != null && l.longitude != null)
                IconButton(
                  icon: const Icon(Icons.directions_outlined),
                  tooltip: 'Open in Maps',
                  onPressed: () =>
                      _openExternal(LatLng(l.latitude!, l.longitude!)),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ListingDetailScreen(listingId: l.id)));
          },
        ),
      ),
    );
  }

  void _showRoadsideReq(RoadsideRequest r) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x33F59E0B),
            child: Icon(Icons.car_repair, color: Color(0xFFF59E0B)),
          ),
          title: Text(r.service),
          subtitle: Text([
            if (r.placeName != null) r.placeName!,
            'Status: ${r.status}',
            if (r.destName != null && r.destName!.isNotEmpty)
              'Drop-off: ${r.destName}',
            if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(1)} km away',
          ].join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.destLatitude != null && r.destLongitude != null)
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: 'Drop-off in Maps',
                  onPressed: () => _openExternal(
                      LatLng(r.destLatitude!, r.destLongitude!)),
                ),
              IconButton(
                icon: const Icon(Icons.directions_outlined),
                tooltip: 'Open in Maps',
                onPressed: () => _openExternal(LatLng(r.latitude, r.longitude)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransitStop(Map<String, dynamic> t) {
    final name = '${t['name'] ?? t['stop_name'] ?? t['title'] ?? 'Transit stop'}';
    final id = t['onestop_id'] ?? t['stop_id'];
    // Next departures the backend already fetched for this stop.
    final deps = _transitDepartures
        .where((d) => id != null && d['stop_id'] == id)
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0x336366F1),
                child:
                    Icon(Icons.directions_transit, color: Color(0xFF6366F1)),
              ),
              title: Text(name),
              subtitle: t['distance'] != null
                  ? Text('${_fmtDistance((_num(t['distance']) ?? 0))} away')
                  : null,
            ),
            if (deps.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text('No upcoming departures.'),
              )
            else
              ...deps.take(8).map(_departureTile),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// A single "next departure" row: route, headsign and minutes-until, with a
  /// live dot + delay when real-time data is available.
  Widget _departureTile(Map<String, dynamic> d) {
    final mins = _num(d['minutes'])?.round();
    final realtime = d['realtime'] == true;
    final delay = _num(d['delay']);
    final when = mins == null
        ? (d['time_label'] ?? '—').toString()
        : (mins <= 0 ? 'Now' : '$mins min');
    String? delayLabel;
    if (realtime && delay != null && delay.abs() >= 60) {
      final m = (delay.abs() / 60).round();
      delayLabel = delay > 0 ? '$m min late' : '$m min early';
    }
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: const Color(0x336366F1),
        child: Text('${d['route'] ?? '—'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4F46E5))),
      ),
      title: Text('${d['headsign'] ?? d['route_long'] ?? 'Service'}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: delayLabel != null ? Text(delayLabel) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (realtime)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.rss_feed, size: 14, color: Color(0xFF22C55E)),
            ),
          Text(when,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Destination + minutes input for starting an ETA share.
class _ShareEtaDialog extends StatefulWidget {
  const _ShareEtaDialog();

  @override
  State<_ShareEtaDialog> createState() => _ShareEtaDialogState();
}

class _ShareEtaDialogState extends State<_ShareEtaDialog> {
  final _destination = TextEditingController();
  int _minutes = 15;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share my ETA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _destination,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Destination',
              hintText: 'Where are you headed?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Arriving in'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _minutes,
                onChanged: (v) => setState(() => _minutes = v ?? _minutes),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 10, child: Text('10 min')),
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                  DropdownMenuItem(value: 45, child: Text('45 min')),
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_destination.text.trim().isEmpty) return;
            Navigator.pop(context, (_destination.text.trim(), _minutes));
          },
          child: const Text('Share'),
        ),
      ],
    );
  }
}

/// "Reviews" row for the saved-place sheet that loads the place's rating
/// summary (★ 4.3 · 27 reviews) and links to the full reviews screen.
class _PlaceReviewsTile extends StatefulWidget {
  const _PlaceReviewsTile({required this.placeKey, required this.onTap});

  final String placeKey;
  final VoidCallback onTap;

  @override
  State<_PlaceReviewsTile> createState() => _PlaceReviewsTileState();
}

class _PlaceReviewsTileState extends State<_PlaceReviewsTile> {
  ReviewSummary? _summary;

  @override
  void initState() {
    super.initState();
    api.guides.placeReviewSummary(widget.placeKey).then((s) {
      if (mounted) setState(() => _summary = s);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final Widget? subtitle = s == null
        ? null
        : (s.count > 0
            ? Text('★ ${s.average.toStringAsFixed(1)} · '
                '${s.count == 1 ? '1 review' : '${s.count} reviews'}')
            : const Text('No reviews yet'));
    return ListTile(
      leading: const Icon(Icons.star_outline),
      title: const Text('Reviews'),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right),
      onTap: widget.onTap,
    );
  }
}

/// Name + category picker for saving a place dropped on the map. Returns
/// (title, category); the category drives the saved-places map filter.
class _SavePlaceDialog extends StatefulWidget {
  const _SavePlaceDialog();

  @override
  State<_SavePlaceDialog> createState() => _SavePlaceDialogState();
}

class _SavePlaceDialogState extends State<_SavePlaceDialog> {
  static const _categories = <(String, IconData)>[
    ('Favorite', Icons.star),
    ('Home', Icons.home_outlined),
    ('Work', Icons.work_outline),
    ('Food', Icons.restaurant),
    ('Shop', Icons.shopping_bag_outlined),
    ('Park', Icons.park_outlined),
    ('Other', Icons.place_outlined),
  ];

  final _name = TextEditingController();
  String _category = 'Favorite';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save place'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Place name', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, icon) in _categories)
                ChoiceChip(
                  avatar: Icon(icon, size: 16),
                  label: Text(label),
                  selected: _category == label,
                  onSelected: (_) => setState(() => _category = label),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    final title = _name.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, (title, _category));
  }
}
