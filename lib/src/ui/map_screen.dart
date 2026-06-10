import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'marketplace_screen.dart';

/// An interactive map with switchable layers — marketplace listings, open
/// roadside requests and nearby transit — plus location search and an
/// adjustable radius (OpenStreetMap tiles, no API key required).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Default view (Toronto) until the user searches or pans.
  static const _fallback = LatLng(43.6532, -79.3832);

  final _controller = MapController();
  final _searchCtrl = TextEditingController();

  LatLng _center = _fallback;
  double _radiusKm = 25;
  bool _showListings = true;
  bool _showRoadside = false;
  bool _showTransit = false;
  bool _loading = false;
  bool _searching = false;

  List<Listing> _listings = const [];
  List<RoadsideRequest> _roadside = const [];
  List<Map<String, dynamic>> _transit = const [];

  /// Active live-ETA share id, when sharing.
  String? _etaShareId;
  String? _etaDestination;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final lat = _center.latitude, lng = _center.longitude;
    try {
      final results = await Future.wait([
        _showListings
            ? api.marketplace
                .listings(lat: lat, lng: lng, radiusKm: _radiusKm)
            : Future.value(const <Listing>[]),
        _showRoadside
            ? api.roadside.nearby(lat: lat, lng: lng, radiusKm: _radiusKm)
            : Future.value(const <RoadsideRequest>[]),
        _showTransit
            ? api.roadside.transitNearby(lat: lat, lng: lng, radius: _radiusKm)
            : Future.value(const <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _listings = results[0] as List<Listing>;
        _roadside = results[1] as List<RoadsideRequest>;
        _transit = results[2] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await api.roadside.geocode(q);
      if (!mounted) return;
      if (results.isEmpty) {
        showInfo(context, 'No places found for “$q”.');
        return;
      }
      final r = results.first;
      final lat = (r['lat'] ?? r['latitude']);
      final lng = (r['lng'] ?? r['lon'] ?? r['longitude']);
      final dLat = lat is num ? lat.toDouble() : double.tryParse('$lat');
      final dLng = lng is num ? lng.toDouble() : double.tryParse('$lng');
      if (dLat == null || dLng == null) {
        showInfo(context, 'Could not locate that place.');
        return;
      }
      _center = LatLng(dLat, dLng);
      _controller.move(_center, 12);
      await _loadAll();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggle(void Function() change) {
    setState(change);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final markers = <Marker>[
      if (_showListings)
        for (final l in _listings)
          if (l.latitude != null && l.longitude != null)
            _marker(LatLng(l.latitude!, l.longitude!), Icons.location_on,
                scheme.primary, () => _showListing(l)),
      if (_showRoadside)
        for (final r in _roadside)
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
    ];

    return Scaffold(
      appBar: AppBar(
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
            icon: const Icon(Icons.tune),
            tooltip: 'Radius',
            onPressed: _radiusSheet,
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
              onPositionChanged: (camera, _) => _center = camera.center,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ca.okayspace.app',
              ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

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
          // Count pill.
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${markers.length} on map · ${_radiusKm.round()} km',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    onPressed: () {
                      Navigator.pop(context);
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
          subtitle: Text('${l.currency} ${l.price.toStringAsFixed(2)}'),
          trailing: const Icon(Icons.chevron_right),
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
