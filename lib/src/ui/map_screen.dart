import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'marketplace_screen.dart';

/// Free, no-API-key tile styles available on the map.
class _TileStyle {
  const _TileStyle(this.id, this.label, this.url, {this.dark = false});
  final String id;
  final String label;
  final String url;
  final bool dark;
}

const _tileStyles = <_TileStyle>[
  _TileStyle('standard', 'Standard',
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  _TileStyle('light', 'Light',
      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png'),
  _TileStyle('dark', 'Dark',
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      dark: true),
  _TileStyle('topo', 'Terrain',
      'https://tile.opentopomap.org/{z}/{x}/{y}.png'),
];

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

  // Filters.
  double _maxPrice = 0; // 0 = no max
  String _roadsideStatus = 'all';
  String _savedCategory = 'all';

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
    } catch (_) {/* ignore */}
  }

  void _savePrefs() {
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

  String _fmtDistance(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} km'
      : '${metres.round()} m';

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
    final items = <(double, String, String, LatLng)>[];
    for (final l in _listings) {
      if (l.latitude != null && l.longitude != null) {
        final pt = LatLng(l.latitude!, l.longitude!);
        items.add((_distance(_center, pt), l.title,
            '${l.currency} ${l.price.toStringAsFixed(0)}', pt));
      }
    }
    for (final r in _roadside) {
      final pt = LatLng(r.latitude, r.longitude);
      items.add((_distance(_center, pt), r.service, r.status, pt));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          children: [
            const ListTile(
                title: Text('Nearest to centre',
                    style: TextStyle(fontWeight: FontWeight.bold))),
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
                  title: const Text('Search as I move the map'),
                  value: _searchAsIMove,
                  onChanged: (v) => setSheet(() {
                    setState(() => _searchAsIMove = v);
                  }),
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
    final zoom = _controller.camera.zoom;
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
              (_maxPrice == 0 || l.price <= _maxPrice))
            _marker(LatLng(l.latitude!, l.longitude!), Icons.location_on,
                scheme.primary, () => _showListing(l)),
      if (_showRoadside)
        for (final r in _roadside)
          if (_roadsideStatus == 'all' ||
              r.status.toLowerCase() == _roadsideStatus)
            _marker(LatLng(r.latitude, r.longitude), Icons.car_repair,
                const Color(0xFFF59E0B), () => _showRoadsideReq(r)),
      if (_showTransit)
        for (final t in _transit)
          if (_num(t['lat'] ?? t['latitude']) != null &&
              _num(t['lon'] ?? t['lng'] ?? t['longitude']) != null)
            _marker(
                LatLng(_num(t['lat'] ?? t['latitude'])!,
                    _num(t['lon'] ?? t['lng'] ?? t['longitude'])!),
                Icons.directions_transit,
                const Color(0xFF6366F1),
                () => _showTransitStop(t)),
      if (_showSaved)
        for (final pl in _saved)
          if (pl.latitude != null &&
              pl.longitude != null &&
              (_savedCategory == 'all' || pl.category == _savedCategory))
            _marker(LatLng(pl.latitude!, pl.longitude!), Icons.bookmark,
                const Color(0xFF10B981), () => _showSavedPlace(pl)),
    ];

    final shownMarkers = _clusterMarkers(markers);
    final radiusMetres = _radiusKm * 1000;

    return Scaffold(
      extendBody: !widget.embedded,
      bottomNavigationBar: widget.embedded ? null : const OkayBottomNav(),
      appBar: OkayAppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: Icon(
                _etaShareId != null ? Icons.share_location : Icons.near_me,
                color: _etaShareId != null ? scheme.primary : null),
            tooltip: _etaShareId != null ? 'Sharing ETA…' : 'Share my ETA',
            onPressed: _etaShareId != null ? _stopEta : _shareEta,
          ),
          IconButton(
            icon: Icon(Icons.straighten,
                color: _measuring ? scheme.primary : null),
            tooltip: 'Measure distance',
            onPressed: _toggleMeasure,
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
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'radius', child: Text('Search radius')),
              PopupMenuItem(value: 'filters', child: Text('Filters')),
              PopupMenuItem(value: 'nearest', child: Text('Nearest to centre')),
              PopupMenuItem(value: 'bookmarks', child: Text('Saved views')),
              PopupMenuItem(value: 'settings', child: Text('Map settings')),
              PopupMenuItem(value: 'legend', child: Text('Legend')),
              PopupMenuItem(value: 'share', child: Text('Share this location')),
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
              onTap: (_, point) => _onTap(point),
              onLongPress: (_, point) => _onLongPress(point),
              onPositionChanged: (camera, hasGesture) {
                _center = camera.center;
                if (camera.rotation != _rotation) {
                  setState(() => _rotation = camera.rotation);
                }
                if (hasGesture && _searchAsIMove) _loadAll();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _style.url,
                userAgentPackageName: 'ca.okayspace.app',
              ),
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
              if (_measuring && _measurePoints.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _measurePoints,
                    strokeWidth: 3,
                    color: scheme.tertiary,
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
                  Marker(
                      point: p,
                      width: 16,
                      height: 16,
                      child: Container(
                          decoration: BoxDecoration(
                              color: scheme.tertiary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2)))),
              ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          if (_showCrosshair)
            const IgnorePointer(
                child: Center(
                    child: Icon(Icons.add, size: 30, color: Colors.black54))),

          // Search bar + layer chips.
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

          // Zoom / compass / recenter controls.
          Positioned(
            right: 12,
            bottom: 76,
            child: Column(
              children: [
                if (_rotation != 0)
                  _mapBtn('compass', Icons.explore, _resetNorth),
                _mapBtn('zoomIn', Icons.add, () => _zoomBy(1)),
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

  Widget _mapBtn(String tag, IconData icon, VoidCallback onTap) =>
      FloatingActionButton.small(
        heroTag: 'map_$tag',
        onPressed: onTap,
        child: Icon(icon),
      );

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
          trailing: IconButton(
            icon: const Icon(Icons.directions_outlined),
            tooltip: 'Open in Maps',
            onPressed: pl.latitude != null && pl.longitude != null
                ? () {
                    Navigator.pop(context);
                    _openExternal(LatLng(pl.latitude!, pl.longitude!));
                  }
                : null,
          ),
        ),
      ),
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color, VoidCallback onTap) {
    return Marker(
      point: point,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(icon, color: color, size: 38, shadows: const [
          Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
        ]),
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
