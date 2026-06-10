import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'marketplace_screen.dart';

/// Mapbox public access token, injected at build time via
/// `--dart-define=MAPBOX_TOKEN=pk...`. When empty the map falls back to
/// free OpenStreetMap/Carto tiles so it still works without a token.
const _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
bool get _hasMapbox => _mapboxToken.isNotEmpty;

/// A selectable basemap. [mapboxStyle] is set for Mapbox styles; otherwise
/// [url] is a plain raster XYZ template.
class _TileStyle {
  const _TileStyle(this.id, this.label,
      {this.url = '', this.mapboxStyle = '', this.dark = false});
  final String id;
  final String label;
  final String url;
  final String mapboxStyle;
  final bool dark;

  bool get isMapbox => mapboxStyle.isNotEmpty;

  /// Resolved tile URL template (Mapbox raster tiles when configured).
  String get tileUrl => isMapbox
      ? 'https://api.mapbox.com/styles/v1/mapbox/$mapboxStyle/tiles/512/{z}/{x}/{y}@2x?access_token=$_mapboxToken'
      : url;
}

const _mapboxStyles = <_TileStyle>[
  _TileStyle('streets', 'Streets', mapboxStyle: 'streets-v12'),
  _TileStyle('outdoors', 'Outdoors', mapboxStyle: 'outdoors-v12'),
  _TileStyle('satellite', 'Satellite',
      mapboxStyle: 'satellite-streets-v12', dark: true),
  _TileStyle('light', 'Light', mapboxStyle: 'light-v11'),
  _TileStyle('dark', 'Dark', mapboxStyle: 'dark-v11', dark: true),
];

const _osmStyles = <_TileStyle>[
  _TileStyle('standard', 'Standard',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  _TileStyle('light', 'Light',
      url: 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png'),
  _TileStyle('dark', 'Dark',
      url: 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      dark: true),
  _TileStyle('topo', 'Terrain',
      url: 'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
];

List<_TileStyle> get _tileStyles => _hasMapbox ? _mapboxStyles : _osmStyles;

/// An interactive map with switchable layers — marketplace listings, open
/// roadside requests and nearby transit — plus location search and an
/// adjustable radius (OpenStreetMap tiles, no API key required).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.embedded = false});

  /// True as a home tab (shell provides the nav); false when pushed standalone.
  final bool embedded;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Default view (Toronto) until the user searches or pans.
  static const _fallback = LatLng(43.6532, -79.3832);

  final _controller = MapController();
  final _searchCtrl = TextEditingController();
  final _storage = const FlutterSecureStorage();

  LatLng _center = _fallback;
  double _radiusKm = 25;
  bool _showListings = true;
  bool _showRoadside = false;
  bool _showTransit = false;
  bool _showSaved = false;
  bool _loading = false;
  bool _searching = false;

  // Display options (persisted).
  String _tileStyle = 'standard';
  bool _showRadiusCircle = true;
  bool _showCrosshair = false;
  bool _cluster = false;
  bool _searchAsIMove = false;
  bool _showGrid = false; // lat/lng graticule
  bool _showLabels = false; // marker title labels
  bool _rotationLocked = false;
  bool _fullscreen = false;
  double _pinSize = 38;
  String _units = 'km'; // 'km' | 'mi'

  // Filters.
  double _maxPrice = 0; // 0 = no max
  double _minPrice = 0;
  bool _withPhotosOnly = false;
  String _roadsideStatus = 'all';
  String _savedCategory = 'all';
  String _nearestSort = 'distance'; // 'distance' | 'price' | 'name'

  // Live centre coordinate readout (kept in state so build never touches the
  // map controller before its first frame, which would throw).
  LatLng _liveCenter = _fallback;
  double _liveZoom = 11;
  bool _mapReady = false;

  // Multi-stop route (waypoints) + straight-line directions target.
  bool _routing = false;
  final List<LatLng> _route = [];
  LatLng? _directionsTo;

  // Polygon area-measure mode.
  bool _areaMode = false;
  final List<LatLng> _areaPoints = [];

  // Search suggestions + recents (persisted).
  List<Map<String, dynamic>> _suggestions = const [];
  List<String> _recent = [];

  // Saved view bookmarks (persisted): {name, lat, lng, zoom}.
  List<Map<String, dynamic>> _bookmarks = [];

  // A manually-set "my location" pin (persisted) and identify pin.
  LatLng? _myLocation;
  LatLng? _identify;

  // Distance-measure tool.
  bool _measuring = false;
  final List<LatLng> _measurePoints = [];

  // Rotation, mirrored from the camera for the compass button.
  double _rotation = 0;

  List<Listing> _listings = const [];
  List<RoadsideRequest> _roadside = const [];
  List<Map<String, dynamic>> _transit = const [];
  List<Place> _saved = const [];

  /// Active live-ETA share id, when sharing.
  String? _etaShareId;
  String? _etaDestination;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

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
          _tileStyle = d['tile'] as String? ?? 'standard';
          _radiusKm = (d['radius'] as num?)?.toDouble() ?? 25;
          _showListings = d['listings'] as bool? ?? true;
          _showRoadside = d['roadside'] as bool? ?? false;
          _showTransit = d['transit'] as bool? ?? false;
          _showSaved = d['saved'] as bool? ?? false;
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
            _liveCenter = _center;
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

  _TileStyle get _style =>
      _tileStyles.firstWhere((s) => s.id == _tileStyle,
          orElse: () => _tileStyles.first);

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
              .transitNearby(
                  lat: lat,
                  lng: lng,
                  radius: (_radiusKm * 1000).clamp(100, 2000).toDouble())
              .catchError((_) => <Map<String, dynamic>>[])
          : Future.value(const <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _listings = results[0] as List<Listing>;
      _roadside = results[1] as List<RoadsideRequest>;
      _transit = results[2] as List<Map<String, dynamic>>;
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

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _suggestions = const [];
    });
    // Allow direct "lat, lng" jumps.
    final coords = _parseCoords(q);
    if (coords != null) {
      _center = coords;
      _controller.move(_center, 13);
      _addRecent(q);
      setState(() => _searching = false);
      await _loadAll();
      return;
    }
    try {
      final results = await api.roadside.geocode(q);
      if (!mounted) return;
      if (results.isEmpty) {
        showInfo(context, 'No places found for “$q”.');
        return;
      }
      _addRecent(q);
      // More than one hit → show a chooser; otherwise jump straight there.
      if (results.length > 1) {
        setState(() => _suggestions = results.cast<Map<String, dynamic>>());
        return;
      }
      _gotoResult(results.first);
      await _loadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
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
      _suggestions = const [];
    });
    _controller.move(_center, 12);
    _loadAll();
  }

  void _toggle(void Function() change) {
    setState(change);
    _savePrefs();
    if (_showSaved && _saved.isEmpty) _loadSaved();
    _loadAll();
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
      final places = await api.roadside.geocode(destQuery);
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
      });
      final url = 'https://okayspace.ca/eta/$shareId';
      Clipboard.setData(ClipboardData(text: url));
      showInfo(context, 'ETA link copied: $url');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _stopEta() async {
    final id = _etaShareId;
    if (id == null) return;
    try {
      await api.roadside.stopEta(id);
    } catch (_) {/* already expired is fine */}
    if (mounted) {
      setState(() {
        _etaShareId = null;
        _etaDestination = null;
      });
      showInfo(context, 'ETA sharing stopped');
    }
  }

  double? _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

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

  // --- Zoom / rotation / recenter -----------------------------------------

  void _zoomBy(double delta) {
    final c = _controller.camera;
    _controller.move(c.center, (c.zoom + delta).clamp(2, 18));
  }

  void _resetNorth() {
    _controller.rotate(0);
    setState(() => _rotation = 0);
  }

  void _recenter() => _controller.move(_center, _controller.camera.zoom);

  void _zoomPreset(double zoom) => _controller.move(_controller.camera.center, zoom);

  void _goToMyLocation() {
    if (_myLocation == null) {
      showInfo(context, 'No location pin set — long-press the map to set one');
      return;
    }
    _controller.move(_myLocation!, 14);
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

  // --- Nearby category quick-search ---------------------------------------

  Future<void> _searchNearby(String category) async {
    setState(() => _searching = true);
    try {
      final c = _controller.camera.center;
      final results = await api.roadside
          .geocode('$category near ${c.latitude},${c.longitude}');
      if (!mounted) return;
      if (results.isEmpty) {
        showInfo(context, 'No "$category" found nearby');
        return;
      }
      setState(() => _suggestions = results.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
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
    if (action == 'mylocation') {
      _setMyLocation(p);
    } else if (action == 'identify') {
      _identifyAt(p);
    } else if (action == 'save') {
      _savePlaceAt(p);
    }
  }

  Future<void> _savePlaceAt(LatLng p) async {
    final title = await promptText(context, title: 'Place name', action: 'Save');
    if (title == null || title.trim().isEmpty) return;
    try {
      await api.guides.addPlace(
          title: title.trim(), latitude: p.latitude, longitude: p.longitude);
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
    if (_measuring) {
      setState(() => _measurePoints.add(p));
    } else if (_routing) {
      setState(() => _route.add(p));
    } else if (_areaMode) {
      setState(() => _areaPoints.add(p));
    }
  }

  // --- External maps / share ----------------------------------------------

  void _openExternal(LatLng p) {
    final url =
        'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}';
    Clipboard.setData(ClipboardData(text: url));
    showInfo(context, 'Maps link copied');
  }

  void _shareThisLocation() {
    final c = _controller.camera.center;
    final url =
        'https://www.openstreetmap.org/?mlat=${c.latitude}&mlon=${c.longitude}#map=${_controller.camera.zoom.round()}/${c.latitude}/${c.longitude}';
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
                      for (final s in _tileStyles)
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
                    if (v) _resetNorth();
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
            _marker(LatLng(r.latitude, r.longitude), Icons.car_repair,
                const Color(0xFFF59E0B), () => _showRoadsideReq(r),
                label: r.service),
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
    ];

    final shownMarkers = _clusterMarkers(markers);
    final radiusMetres = _radiusKm * 1000;

    return Scaffold(
      extendBody: !widget.embedded,
      bottomNavigationBar: widget.embedded ? null : const OkayBottomNav(),
      appBar: _fullscreen
          ? null
          : OkayAppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: Icon(
                _etaShareId != null ? Icons.share_location : Icons.near_me,
                color: _etaShareId != null ? scheme.primary : null),
            tooltip: _etaShareId != null ? 'Sharing ETA…' : 'Share my ETA',
            onPressed: _etaShareId != null ? _stopEta : _shareEta,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.architecture,
                color: (_measuring || _routing || _areaMode)
                    ? scheme.primary
                    : null),
            tooltip: 'Tools',
            onSelected: (v) {
              switch (v) {
                case 'measure':
                  _toggleMeasure();
                case 'route':
                  _toggleRouting();
                case 'area':
                  _toggleArea();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: 'measure',
                  checked: _measuring,
                  child: const Text('Measure distance')),
              CheckedPopupMenuItem(
                  value: 'route',
                  checked: _routing,
                  child: const Text('Build a route')),
              CheckedPopupMenuItem(
                  value: 'area',
                  checked: _areaMode,
                  child: const Text('Measure area')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Fullscreen',
            onPressed: () => setState(() => _fullscreen = true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'radius':
                  _radiusSheet();
                case 'filters':
                  _filtersSheet();
                case 'settings':
                  _settingsSheet();
                case 'bookmarks':
                  _bookmarksSheet();
                case 'nearest':
                  _nearestSheet();
                case 'legend':
                  _legendSheet();
                case 'share':
                  _shareThisLocation();
                case 'savecentre':
                  _savePlaceAtCenter();
                case 'copycentre':
                  _copyCenter();
                case 'fit':
                  _fitAll();
                case 'reset':
                  _resetAll();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'radius', child: Text('Search radius')),
              PopupMenuItem(value: 'filters', child: Text('Filters')),
              PopupMenuItem(value: 'nearest', child: Text('Nearest to centre')),
              PopupMenuItem(value: 'fit', child: Text('Fit all markers')),
              PopupMenuItem(value: 'bookmarks', child: Text('Saved views')),
              PopupMenuItem(
                  value: 'savecentre', child: Text('Save centre as place')),
              PopupMenuItem(value: 'copycentre', child: Text('Copy centre coords')),
              PopupMenuItem(value: 'settings', child: Text('Map settings')),
              PopupMenuItem(value: 'legend', child: Text('Legend')),
              PopupMenuItem(value: 'share', child: Text('Share this location')),
              PopupMenuItem(value: 'reset', child: Text('Reset all')),
            ],
          ),
        ],
      ),
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
                setState(() {
                  _liveCenter = _controller.camera.center;
                  _liveZoom = _controller.camera.zoom;
                });
              },
              onTap: (_, point) => _onTap(point),
              onLongPress: (_, point) => _onLongPress(point),
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
                if (camera.rotation != _rotation ||
                    camera.center != _liveCenter ||
                    camera.zoom != _liveZoom) {
                  setState(() {
                    _rotation = camera.rotation;
                    _liveCenter = camera.center;
                    _liveZoom = camera.zoom;
                  });
                }
                if (hasGesture && _searchAsIMove) _loadAll();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _style.tileUrl,
                userAgentPackageName: 'ca.okayspace.app',
                tileSize: _style.isMapbox ? 512 : 256,
                zoomOffset: _style.isMapbox ? -1 : 0,
                additionalOptions: _style.isMapbox
                    ? const {'token': _mapboxToken}
                    : const {},
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
              MarkerLayer(markers: [
                ...shownMarkers,
                if (_myLocation != null)
                  _marker(_myLocation!, Icons.my_location,
                      const Color(0xFF2563EB), () {}),
                if (_identify != null)
                  _marker(_identify!, Icons.place, const Color(0xFFEF4444),
                      () => _identifyAt(_identify!)),
                for (final p in _measurePoints)
                  _dot(p, scheme.tertiary),
                for (final p in _route) _dot(p, scheme.primary),
                for (final p in _areaPoints) _dot(p, scheme.tertiary),
              ]),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(_style.isMapbox
                      ? '© Mapbox © OpenStreetMap'
                      : '© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          if (_showCrosshair)
            const IgnorePointer(
                child: Center(
                    child: Icon(Icons.add, size: 30, color: Colors.black54))),

          // Search bar + layer chips.
          if (!_fullscreen)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Column(
              children: [
                Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(14),
                  color: scheme.surface,
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Search a place or address',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : IconButton(
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: _search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                // Search suggestions (multiple geocode hits).
                if (_suggestions.isNotEmpty)
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(14),
                    color: scheme.surface,
                    child: Column(
                      children: [
                        for (final r in _suggestions.take(6))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                                '${r['name'] ?? r['display_name'] ?? r['label'] ?? 'Result'}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              _gotoResult(r);
                              _loadAll();
                            },
                          ),
                      ],
                    ),
                  ),
                // Recent searches.
                if (_suggestions.isEmpty &&
                    _searchCtrl.text.isEmpty &&
                    _recent.isNotEmpty)
                  SizedBox(
                    height: 38,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final q in _recent)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                avatar: const Icon(Icons.history, size: 16),
                                label: Text(q),
                                onPressed: () {
                                  _searchCtrl.text = q;
                                  _search();
                                },
                              ),
                            ),
                          ActionChip(
                            label: const Text('Clear'),
                            onPressed: _clearRecents,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _layerChip('Listings', Icons.storefront, _showListings,
                          () => _toggle(() => _showListings = !_showListings)),
                      const SizedBox(width: 8),
                      _layerChip('Roadside', Icons.car_repair, _showRoadside,
                          () => _toggle(() => _showRoadside = !_showRoadside)),
                      const SizedBox(width: 8),
                      _layerChip('Transit', Icons.directions_transit,
                          _showTransit,
                          () => _toggle(() => _showTransit = !_showTransit)),
                      const SizedBox(width: 8),
                      _layerChip('Saved', Icons.bookmark, _showSaved,
                          () => _toggle(() => _showSaved = !_showSaved)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final cat in const [
                        ('Cafés', 'cafe'),
                        ('Gas', 'gas station'),
                        ('Parking', 'parking'),
                        ('Food', 'restaurant'),
                        ('Hospitals', 'hospital'),
                        ('Parks', 'park'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(cat.$1),
                            onPressed: () => _searchNearby(cat.$2),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_loading)
            const Positioned(
              top: 120,
              right: 16,
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
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

          // Live centre coordinate readout.
          if (!_fullscreen)
            Positioned(
              top: _measuring || _routing || _areaMode ? 160 : 110,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    'z${_liveZoom.toStringAsFixed(1)} · ${_liveCenter.latitude.toStringAsFixed(3)}, ${_liveCenter.longitude.toStringAsFixed(3)}',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),

          // Zoom / compass / recenter controls.
          Positioned(
            right: 12,
            bottom: 76,
            child: Column(
              children: [
                if (_fullscreen)
                  _mapBtn('exitFs', Icons.fullscreen_exit,
                      () => setState(() => _fullscreen = false)),
                if (_fullscreen) const SizedBox(height: 8),
                if (_rotation != 0)
                  _mapBtn('compass', Icons.explore, _resetNorth),
                if (_myLocation != null)
                  _mapBtn('myloc', Icons.my_location, _goToMyLocation),
                if (_myLocation != null) const SizedBox(height: 8),
                _mapBtn('fit', Icons.fit_screen, _fitAll),
                const SizedBox(height: 8),
                _mapBtn('zoomIn', Icons.add, () => _zoomBy(1),
                    onLongPress: _zoomPresetSheet),
                const SizedBox(height: 8),
                _mapBtn('zoomOut', Icons.remove, () => _zoomBy(-1)),
                const SizedBox(height: 8),
                _mapBtn('recenter', Icons.center_focus_strong, _recenter),
              ],
            ),
          ),

          // Count pill.
          Positioned(
            left: 12,
            bottom: 12,
            child: GestureDetector(
              onTap: _nearestSheet,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_countLabel(markers.length),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),

          // Search-this-area button.
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton.extended(
              heroTag: 'searchArea',
              onPressed: _loadAll,
              icon: const Icon(Icons.refresh),
              label: const Text('Search this area'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapBtn(String tag, IconData icon, VoidCallback onTap,
          {VoidCallback? onLongPress}) =>
      GestureDetector(
        onLongPress: onLongPress,
        child: FloatingActionButton.small(
          heroTag: 'map_$tag',
          onPressed: onTap,
          child: Icon(icon),
        ),
      );

  void _zoomPresetSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Zoom to',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final z in const [
              ('Street', 16.0),
              ('Neighbourhood', 14.0),
              ('City', 11.0),
              ('Region', 8.0),
              ('Country', 5.0),
            ])
              ListTile(
                title: Text(z.$1),
                onTap: () {
                  Navigator.pop(context);
                  _zoomPreset(z.$2);
                },
              ),
          ],
        ),
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

  /// A short breakdown of what's on the map, by active layer.
  String _countLabel(int total) {
    final parts = <String>[];
    if (_showListings && _listings.isNotEmpty) parts.add('${_listings.length} 🛍');
    if (_showRoadside && _roadside.isNotEmpty) parts.add('${_roadside.length} 🚗');
    if (_showTransit && _transit.isNotEmpty) parts.add('${_transit.length} 🚆');
    if (_showSaved && _saved.isNotEmpty) parts.add('${_saved.length} 🔖');
    final breakdown = parts.isEmpty ? '$total on map' : parts.join(' · ');
    return '$breakdown · ${_radiusKm.round()} km';
  }

  void _showSavedPlace(Place pl) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
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
      ),
    );
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
            if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(1)} km away',
          ].join(' · ')),
          trailing: IconButton(
            icon: const Icon(Icons.directions_outlined),
            tooltip: 'Open in Maps',
            onPressed: () =>
                _openExternal(LatLng(r.latitude, r.longitude)),
          ),
        ),
      ),
    );
  }

  void _showTransitStop(Map<String, dynamic> t) {
    final name = '${t['name'] ?? t['stop_name'] ?? t['title'] ?? 'Transit stop'}';
    final lines = t['lines'] ?? t['routes'];
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0x336366F1),
            child: Icon(Icons.directions_transit, color: Color(0xFF6366F1)),
          ),
          title: Text(name),
          subtitle: lines is List && lines.isNotEmpty
              ? Text('Lines: ${lines.join(', ')}')
              : null,
        ),
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
