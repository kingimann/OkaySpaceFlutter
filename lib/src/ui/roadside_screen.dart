import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../okayspace_api.dart';
import '../core/device_location.dart';
import 'common.dart';

const _services = <(String, String, IconData)>[
  ('fuel', 'Out of fuel', Icons.local_gas_station),
  ('battery', 'Battery / jump start', Icons.battery_charging_full),
  ('tire', 'Flat tire', Icons.tire_repair),
  ('lockout', 'Locked out', Icons.lock_outline),
  ('tow', 'Tow', Icons.local_shipping),
  ('other', 'Something else', Icons.build_outlined),
];

String _serviceLabel(String key) =>
    _services.firstWhere((s) => s.$1 == key, orElse: () => (key, key, Icons.help_outline)).$2;

IconData _serviceIcon(String key) => _services
    .firstWhere((s) => s.$1 == key, orElse: () => ('', '', Icons.help_outline))
    .$3;

/// Phase detection tolerant of both the model booleans and status strings
/// (the backend can express en-route/arrived either way).
bool _isEnRoute(RoadsideRequest r) {
  final s = r.status.toLowerCase();
  return r.enRoute || s == 'enroute' || s == 'en_route';
}

bool _isArrived(RoadsideRequest r) =>
    r.arrived || r.status.toLowerCase() == 'arrived';

/// A status pill color for a roadside request.
Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
    case 'open':
      return const Color(0xFFF59E0B);
    case 'accepted':
    case 'enroute':
    case 'en_route':
    case 'arrived':
      return const Color(0xFF06B6D4);
    case 'completed':
      return const Color(0xFF22C55E);
    case 'cancelled':
    case 'canceled':
    case 'disputed':
      return const Color(0xFFF43F5E);
    default:
      return const Color(0xFF8696A0);
  }
}

/// Roadside assistance: tabbed view of your requests, nearby calls to help
/// with, requests you're helping, and history.
class RoadsideScreen extends StatefulWidget {
  const RoadsideScreen({super.key});

  @override
  State<RoadsideScreen> createState() => _RoadsideScreenState();
}

class _RoadsideScreenState extends State<RoadsideScreen> {
  // Search origin: device GPS when granted, downtown Toronto until then.
  static const _fallbackLat = 43.6532, _fallbackLng = -79.3832;
  double _lat = _fallbackLat;
  double _lng = _fallbackLng;

  /// Nearby search radius, adjustable from the Nearby tab.
  double _radiusKm = 50;

  /// Nearby presentation: list or map.
  bool _nearbyMap = false;

  late Future<List<RoadsideRequest>> _mine;
  late Future<dynamic> _active;
  late Future<List<RoadsideRequest>> _nearby;
  late Future<List<RoadsideRequest>> _helping;
  late Future<List<RoadsideRequest>> _history;

  @override
  void initState() {
    super.initState();
    _load();
    // Re-run nearby around the real position once GPS resolves.
    currentLatLng().then((pos) {
      if (pos != null && mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _nearby =
              api.roadside.nearby(lat: _lat, lng: _lng, radiusKm: _radiusKm);
        });
      }
    });
  }

  void _load() {
    _mine = api.roadside.mine();
    _active = api.roadside.active().catchError((_) => null);
    _nearby = api.roadside.nearby(lat: _lat, lng: _lng, radiusKm: _radiusKm);
    _helping = api.roadside.helping();
    _history = api.roadside.history();
  }

  Future<void> _reload() async {
    setState(_load);
    // Hold the refresh indicator until every tab's fetch settles.
    await Future.wait<void>([
      for (final f in [_mine, _nearby, _helping, _history])
        f.then<void>((_) {}).catchError((_) {}),
      _active.then<void>((_) {}).catchError((_) {}),
    ]);
  }

  Future<void> _request() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const RoadsideRequestForm(),
    ));
    if (created == true && mounted) _reload();
  }

  Future<void> _open(RoadsideRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoadsideDetailScreen(requestId: r.id),
    ));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: const OkayAppBar(
          title: Text('Roadside assistance'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'My requests'),
              Tab(text: 'Nearby'),
              Tab(text: 'Helping'),
              Tab(text: 'History'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _request,
          icon: const Icon(Icons.add_alert),
          label: const Text('Request help'),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [
              _mineTab(),
              _nearbyTab(),
              _helpingTab(),
              _list(_history, 'No past requests.'),
            ],
          ),
        ),
      ),
    );
  }

  /// My requests, with the live request (if any) as a hero card up top.
  Widget _mineTab() {
    return Column(
      children: [
        FutureBuilder<dynamic>(
          future: _active,
          builder: (context, snap) {
            final d = snap.data;
            final m = d is Map
                ? (d['request'] is Map ? d['request'] as Map : d)
                : null;
            if (m == null || '${m['id'] ?? ''}'.isEmpty) {
              return const SizedBox.shrink();
            }
            final r = RoadsideRequest.fromJson(Map<String, dynamic>.from(m));
            final color = _statusColor(r.status);
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Material(
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(r),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, darken(color, 0.25)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(_serviceIcon(r.service),
                            color: Colors.white, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Active: ${_serviceLabel(r.service)}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              Text(
                                  _isArrived(r)
                                      ? 'Your helper has arrived'
                                      : _isEnRoute(r)
                                          ? 'Help is on the way'
                                          : r.status.toLowerCase() ==
                                                  'accepted'
                                              ? 'A helper accepted — waiting to depart'
                                              : 'Waiting for a helper…',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: _list(_mine,
              'No roadside requests.\nTap “Request help” if you’re stuck.'),
        ),
      ],
    );
  }

  /// Helping tab: lifetime helper stats over the active list.
  Widget _helpingTab() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        FutureBuilder<List<RoadsideRequest>>(
          future: _history,
          builder: (context, snap) {
            final done = (snap.data ?? const <RoadsideRequest>[])
                .where((r) =>
                    r.helping && r.status.toLowerCase() == 'completed')
                .toList();
            if (done.isEmpty) return const SizedBox.shrink();
            final earned =
                done.fold<num>(0, (a, r) => a + r.total);
            Widget stat(String label, String value) => Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                        Text(label,
                            style: TextStyle(
                                color: scheme.outline, fontSize: 11)),
                      ],
                    ),
                  ),
                );
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                stat('Rescues completed', '${done.length}'),
                const SizedBox(width: 10),
                stat('Value of rescues', '\$${earned.toStringAsFixed(2)}'),
              ]),
            );
          },
        ),
        Expanded(
          child:
              _list(_helping, "You're not helping with any requests."),
        ),
      ],
    );
  }

  /// Nearby tab: a radius selector over the standard list.
  Widget _nearbyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Text('Within',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13)),
              const SizedBox(width: 10),
              for (final km in const [10.0, 25.0, 50.0, 100.0])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${km.toInt()} km'),
                    selected: _radiusKm == km,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() {
                      _radiusKm = km;
                      _nearby = api.roadside
                          .nearby(lat: _lat, lng: _lng, radiusKm: km);
                    }),
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: Icon(_nearbyMap ? Icons.view_list : Icons.map_outlined,
                    size: 20),
                visualDensity: VisualDensity.compact,
                tooltip: _nearbyMap ? 'List view' : 'Map view',
                onPressed: () => setState(() => _nearbyMap = !_nearbyMap),
              ),
            ],
          ),
        ),
        Expanded(
          child: _nearbyMap
              ? _nearbyMapView()
              : _list(_nearby, 'No open requests nearby right now.'),
        ),
      ],
    );
  }

  /// Nearby requests as pins on a map; tapping a pin opens the request.
  Widget _nearbyMapView() {
    return FutureBuilder<List<RoadsideRequest>>(
      future: _nearby,
      builder: (context, snap) {
        if (snap.hasError) {
          return CenteredMessage(
              message: messageFor(snap.error), icon: Icons.error_outline);
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(_lat, _lng),
                initialZoom: 10,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ca.okayspace.app',
                ),
                MarkerLayer(markers: [
                  for (final r in items)
                    Marker(
                      point: LatLng(r.latitude, r.longitude),
                      width: 44,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _open(r),
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: _statusColor(r.status),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 1.5),
                            ),
                            child: Icon(_serviceIcon(r.service),
                                size: 16, color: Colors.white),
                          ),
                          const Icon(Icons.arrow_drop_down,
                              size: 16, color: Colors.black54),
                        ]),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(Future<List<RoadsideRequest>> future, String empty) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<RoadsideRequest>(
        future: future,
        loading: const ListSkeleton(),
        emptyMessage: empty,
        emptyIcon: Icons.car_repair,
        builder: (context, items) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = items[i];
            final color = _statusColor(r.status);
            // Card with a colored status stripe down the left edge.
            return Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _open(r),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  color.withValues(alpha: 0.16),
                              child: Icon(_serviceIcon(r.service),
                                  color: color, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(_serviceLabel(r.service),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                      [
                                        if (r.placeName != null)
                                          r.placeName!,
                                        shortAgo(r.createdAt),
                                        if (r.distanceKm != null)
                                          '${r.distanceKm!.toStringAsFixed(1)} km',
                                        if (r.total > 0)
                                          '\$${r.total.toStringAsFixed(2)}',
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: scheme.outline,
                                          fontSize: 12.5)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(status: r.status),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(
              color: c, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

/// Horizontal lifecycle stepper: requested → accepted → en route → arrived
/// → done, with the reached steps filled in the status color.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.request});

  final RoadsideRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = request.status.toLowerCase();
    final cancelled = status == 'cancelled' ||
        status == 'canceled' ||
        status == 'disputed';
    final reached = cancelled
        ? 0
        : status == 'completed'
            ? 4
            : _isArrived(request)
                ? 3
                : _isEnRoute(request)
                    ? 2
                    : (status == 'accepted' ? 1 : 0);
    final color = _statusColor(request.status);
    const labels = ['Requested', 'Accepted', 'En route', 'Arrived', 'Done'];

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                color: i <= reached
                    ? color
                    : scheme.surfaceContainerHighest,
              ),
            ),
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= reached
                      ? color
                      : scheme.surfaceContainerHighest,
                ),
                child: i <= reached
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(labels[i],
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight:
                          i == reached ? FontWeight.bold : FontWeight.normal,
                      color: i <= reached ? null : scheme.outline)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Full request detail with the lifecycle actions appropriate to the viewer
/// (requester vs. helper) and the current status.
class RoadsideDetailScreen extends StatefulWidget {
  const RoadsideDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<RoadsideDetailScreen> createState() => _RoadsideDetailScreenState();
}

class _RoadsideDetailScreenState extends State<RoadsideDetailScreen> {
  late Future<RoadsideRequest> _req;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _req = api.roadside.get(widget.requestId);
  }

  Future<void> _do(Future<RoadsideRequest> Function() op, String ok) async {
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) {
        showInfo(context, ok);
        setState(() => _req = api.roadside.get(widget.requestId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => const _ReviewDialog(),
    );
    if (result == null) return;
    _do(() => api.roadside.review(widget.requestId,
        rating: result.$1, text: result.$2.isEmpty ? null : result.$2),
        'Thanks for your review');
  }

  /// Nearby public transit around the breakdown spot — a no-car fallback
  /// while waiting (or if the request falls through).
  Future<void> _transitNearby(RoadsideRequest r) async {
    final future = api.roadside
        .transitNearby(lat: r.latitude, lng: r.longitude, radius: 1200);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (sheetContext, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(messageFor(snap.error))),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final stops = snap.data!;
            if (stops.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                    child: Text('No transit stops found nearby.')),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                const ListTile(
                    title: Text('Transit nearby',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                for (final stop in stops.take(12))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.directions_bus_outlined),
                    title: Text(
                        '${stop['name'] ?? stop['title'] ?? stop['stop_name'] ?? 'Stop'}'),
                    subtitle: Text(
                      [
                        if (stop['lines'] is List)
                          (stop['lines'] as List).join(', ')
                        else if (stop['routes'] is List)
                          (stop['routes'] as List).join(', '),
                        if (stop['distance'] != null)
                          '${stop['distance']} m',
                      ].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Starts a live ETA share toward the request location (helper side).
  Future<void> _shareEta(RoadsideRequest r) async {
    final raw = await promptText(context,
        title: 'Share my ETA',
        hint: 'Minutes away (e.g. 15)',
        action: 'Share');
    final minutes = int.tryParse(raw ?? '');
    if (minutes == null || minutes <= 0 || !mounted) return;
    try {
      await api.roadside.startEta(
        name: 'Roadside help',
        destinationName: r.placeName,
        destinationLatitude: r.latitude,
        destinationLongitude: r.longitude,
        etaMinutes: minutes,
        ttlMinutes: minutes + 60,
      );
      if (mounted) {
        showInfo(context, 'ETA shared — $minutes min out');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _verify() async {
    final code = await promptText(context,
        title: 'Enter completion code',
        hint: '6-digit code from the helper',
        action: 'Verify');
    if (code == null) return;
    _do(() => api.roadside.verify(widget.requestId, code), 'Verified');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Request')),
      body: MaxWidth(
        child: FutureBuilder<RoadsideRequest>(
          future: _req,
          builder: (context, snap) {
            if (snap.hasError) {
              return CenteredMessage(
                  message: messageFor(snap.error),
                  icon: Icons.error_outline,
                  onRetry: () => setState(
                      () => _req = api.roadside.get(widget.requestId)));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final r = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          _statusColor(r.status).withValues(alpha: 0.18),
                      child: Icon(_serviceIcon(r.service),
                          color: _statusColor(r.status), size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_serviceLabel(r.service),
                              style: Theme.of(context).textTheme.titleLarge),
                          if (r.callNumber != null)
                            Text('Call #${r.callNumber}',
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    _StatusPill(status: r.status),
                  ],
                ),
                const SizedBox(height: 16),
                _Timeline(request: r),
                const SizedBox(height: 16),
                // Where the vehicle is — helpers can see at a glance.
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 160,
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(r.latitude, r.longitude),
                          initialZoom: 13,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'ca.okayspace.app',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(r.latitude, r.longitude),
                              width: 36,
                              height: 36,
                              child: const Icon(Icons.location_pin,
                                  color: Color(0xFFEF4444), size: 36),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.directions_outlined, size: 18),
                    label: const Text('Get directions'),
                    onPressed: () => launchUrl(
                      Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=${r.latitude},${r.longitude}'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
                _row(Icons.place_outlined, r.placeName ?? 'Location set'),
                if (r.destName != null && r.destName!.isNotEmpty)
                  _row(Icons.flag_outlined, 'Drop-off: ${r.destName}'),
                if (r.vehicleMake != null || r.vehicleModel != null)
                  _row(Icons.directions_car_outlined,
                      [r.vehicleColor, r.vehicleMake, r.vehicleModel]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' ')),
                if (r.note != null && r.note!.isNotEmpty)
                  _row(Icons.notes, r.note!),
                if (r.total > 0)
                  _row(Icons.attach_money,
                      'Total \$${r.total.toStringAsFixed(2)}'),
                if (r.distanceKm != null)
                  _row(Icons.straighten,
                      '${r.distanceKm!.toStringAsFixed(1)} km away'),
                if (r.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: r.photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog.fullscreen(
                            backgroundColor: Colors.black,
                            child: Stack(children: [
                              Center(
                                  child: InteractiveViewer(
                                      child: Image.network(r.photos[i]))),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.white),
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                ),
                              ),
                            ]),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(r.photos[i],
                              width: 110, height: 84, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ..._actions(r),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );

  /// Lifecycle buttons depend on whether the request is mine, I'm helping,
  /// and the status.
  List<Widget> _actions(RoadsideRequest r) {
    final status = r.status.toLowerCase();
    final btns = <Widget>[];

    FilledButton big(String label, IconData icon, VoidCallback onTap,
            {Color? color}) =>
        FilledButton.icon(
          onPressed: _busy ? null : onTap,
          icon: Icon(icon),
          label: Text(label),
          style: color != null
              ? FilledButton.styleFrom(backgroundColor: color)
              : null,
        );

    if (r.mine) {
      if (r.isActive) {
        btns.add(big('Cancel request', Icons.cancel_outlined,
            () => _do(() => api.roadside.cancel(r.id), 'Cancelled'),
            color: Theme.of(context).colorScheme.error));
        btns.add(const SizedBox(height: 10));
        btns.add(OutlinedButton.icon(
          onPressed: _busy ? null : _verify,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Enter completion code'),
        ));
        btns.add(const SizedBox(height: 10));
        btns.add(TextButton.icon(
          onPressed: _busy ? null : () => _transitNearby(r),
          icon: const Icon(Icons.directions_bus_outlined, size: 18),
          label: const Text('No car needed? Transit nearby'),
        ));
      }
      if (status == 'completed' && (r.canReview ?? false)) {
        btns.add(big('Leave a review', Icons.star_outline, _review));
      }
      if (r.canDispute ?? false) {
        btns.add(const SizedBox(height: 10));
        btns.add(OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _do(() => api.roadside.dispute(r.id), 'Dispute opened'),
          icon: const Icon(Icons.gavel_outlined),
          label: const Text('Open a dispute'),
        ));
      }
    } else {
      // Helper view.
      if (r.helping) {
        if (!_isEnRoute(r)) {
          btns.add(big("I'm on my way", Icons.directions_car,
              () => _do(() => api.roadside.enroute(r.id), 'Marked en route')));
        } else if (!_isArrived(r)) {
          btns.add(OutlinedButton.icon(
            onPressed: _busy ? null : () => _shareEta(r),
            icon: const Icon(Icons.share_location_outlined),
            label: const Text('Share my ETA'),
          ));
          btns.add(const SizedBox(height: 10));
          btns.add(big("I've arrived", Icons.flag,
              () => _do(() => api.roadside.arrived(r.id), 'Marked arrived')));
        } else {
          btns.add(const Text('Waiting for the requester to confirm…'));
        }
      } else if (status == 'pending' || status == 'open') {
        btns.add(big('Accept & help', Icons.volunteer_activism,
            () => _do(() => api.roadside.accept(r.id), 'You accepted'),
            color: const Color(0xFF22C55E)));
      }
    }

    if (btns.isEmpty) {
      btns.add(Center(
        child: Text('No actions available.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ));
    }
    return btns;
  }
}

/// A 1–5 star review with optional text.
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 5;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leave a review'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(i <= _rating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF59E0B)),
                ),
            ],
          ),
          TextField(
            controller: _text,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Comments (optional)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, (_rating, _text.text.trim())),
            child: const Text('Submit')),
      ],
    );
  }
}

/// Form to create a roadside request.
class RoadsideRequestForm extends StatefulWidget {
  const RoadsideRequestForm({super.key});

  @override
  State<RoadsideRequestForm> createState() => _RoadsideRequestFormState();
}

class _RoadsideRequestFormState extends State<RoadsideRequestForm> {
  String _service = _services.first.$1;
  final _place = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _note = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();

  /// Resolved location (via search or manual entry).
  double? _pickedLat;
  double? _pickedLng;
  String? _pickedName;

  Future<List<Map<String, dynamic>>>? _geoResults;
  Timer? _geoDebounce;

  /// Service price table from /roadside/quote (best-effort).
  Map<String, dynamic> _quote = const {};

  // Tow drop-off (required when service == 'tow').
  final _drop = TextEditingController();
  double? _dropLat;
  double? _dropLng;
  String? _dropName;
  Future<List<Map<String, dynamic>>>? _dropResults;
  Timer? _dropDebounce;

  void _onDropQuery(String q) {
    if (_dropName != null && q.trim() != _dropName) {
      setState(() {
        _dropLat = null;
        _dropLng = null;
        _dropName = null;
      });
    }
    _dropDebounce?.cancel();
    _dropDebounce = Timer(const Duration(milliseconds: 400), () {
      final query = q.trim();
      if (!mounted) return;
      if (query.length < 3) {
        setState(() => _dropResults = null);
        return;
      }
      setState(() => _dropResults = api.roadside.geocode(query));
    });
  }

  void _pickDrop(Map<String, dynamic> g) {
    final lat = double.tryParse('${g['lat'] ?? g['latitude']}');
    final lng = double.tryParse('${g['lng'] ?? g['lon'] ?? g['longitude']}');
    if (lat == null || lng == null) return;
    setState(() {
      _dropLat = lat;
      _dropLng = lng;
      _dropName =
          '${g['name'] ?? g['display_name'] ?? g['label'] ?? _drop.text.trim()}';
      _dropResults = null;
      _drop.text = _dropName!;
    });
  }

  /// Photos of the situation (helps helpers bring the right gear).
  final List<Uint8List> _photos = [];

  Future<void> _addPhotos() async {
    try {
      // Kept small: six base64 photos must fit one JSON body.
      final picked = await ImagePicker().pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      for (final f in picked.take(6 - _photos.length)) {
        _photos.add(await f.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
  bool _manualCoords = false;
  String _fuelType = 'regular';
  String _payment = 'wallet';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    api.roadside.quote().then((d) {
      if (mounted && d is Map) {
        setState(() => _quote = Map<String, dynamic>.from(d));
      }
    }).catchError((_) {});
  }

  /// The quoted price for [service], hunting through common payload shapes.
  num? _priceFor(String service) {
    dynamic v = _quote[service] ??
        (_quote['prices'] is Map ? (_quote['prices'] as Map)[service] : null) ??
        (_quote['services'] is Map
            ? (_quote['services'] as Map)[service]
            : null);
    if (v is Map) v = v['price'] ?? v['total'] ?? v['amount'];
    return v is num ? v : num.tryParse('$v');
  }

  @override
  void dispose() {
    _geoDebounce?.cancel();
    _dropDebounce?.cancel();
    for (final c in [_place, _make, _model, _note, _lat, _lng, _drop]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPlaceQuery(String q) {
    // Editing the text invalidates a previously picked location immediately —
    // otherwise the form would submit the old coordinates under new text.
    if (_pickedName != null && q.trim() != _pickedName) {
      setState(() {
        _pickedLat = null;
        _pickedLng = null;
        _pickedName = null;
      });
    }
    _geoDebounce?.cancel();
    _geoDebounce = Timer(const Duration(milliseconds: 400), () {
      final query = q.trim();
      if (!mounted) return;
      if (query.length < 3) {
        setState(() => _geoResults = null); // clear stale suggestions
        return;
      }
      setState(() => _geoResults = api.roadside.geocode(query));
    });
  }

  void _pickGeo(Map<String, dynamic> g) {
    final lat = double.tryParse('${g['lat'] ?? g['latitude']}');
    final lng = double.tryParse('${g['lng'] ?? g['lon'] ?? g['longitude']}');
    if (lat == null || lng == null) return;
    setState(() {
      _pickedLat = lat;
      _pickedLng = lng;
      _pickedName =
          '${g['name'] ?? g['display_name'] ?? g['label'] ?? _place.text.trim()}';
      _geoResults = null;
      _place.text = _pickedName!;
    });
  }

  void _applyManual() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      showInfo(context, 'Enter a valid latitude and longitude.');
      return;
    }
    setState(() {
      _pickedLat = lat;
      _pickedLng = lng;
      _pickedName = _place.text.trim().isEmpty
          ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
          : _place.text.trim();
    });
  }

  Future<void> _submit() async {
    final lat = _pickedLat;
    final lng = _pickedLng;
    if (lat == null || lng == null) {
      showInfo(context, 'Pick your location first.');
      return;
    }
    if (_service == 'tow' && (_dropLat == null || _dropLng == null)) {
      showInfo(context, 'Pick a drop-off location for the tow.');
      return;
    }
    setState(() => _busy = true);
    try {
      await api.roadside.create(
        service: _service,
        latitude: lat,
        longitude: lng,
        placeName: _pickedName,
        vehicleMake: _make.text.trim().isEmpty ? null : _make.text.trim(),
        vehicleModel: _model.text.trim().isEmpty ? null : _model.text.trim(),
        fuelType: _service == 'fuel' ? _fuelType : null,
        paymentMethod: _payment,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photos: [
          for (final b in _photos)
            'data:image/jpeg;base64,${base64Encode(b)}',
        ],
        destName: _service == 'tow' ? _dropName : null,
        destLatitude: _service == 'tow' ? _dropLat : null,
        destLongitude: _service == 'tow' ? _dropLng : null,
      );
      if (mounted) {
        showInfo(context, 'Request submitted — help is on the way');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6)),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final located = _pickedLat != null && _pickedLng != null;
    final dropSet = _service != 'tow' || (_dropLat != null && _dropLng != null);

    return Scaffold(
      appBar: const OkayAppBar(title: Text('Request help')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('What do you need?'),
            // Service grid: big tappable cards instead of cramped chips.
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final svc in _services)
                  Material(
                    color: _service == svc.$1
                        ? scheme.primary.withValues(alpha: 0.16)
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _service = svc.$1),
                      child: Container(
                        decoration: _service == svc.$1
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: scheme.primary, width: 1.5),
                              )
                            : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(svc.$3,
                                size: 26,
                                color: _service == svc.$1
                                    ? scheme.primary
                                    : scheme.outline),
                            const SizedBox(height: 6),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(svc.$2,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: _service == svc.$1
                                          ? FontWeight.bold
                                          : FontWeight.w500)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_service == 'fuel') ...[
              _sectionTitle('Fuel type'),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in const ['regular', 'premium', 'diesel'])
                    ChoiceChip(
                      label: Text(f[0].toUpperCase() + f.substring(1)),
                      selected: _fuelType == f,
                      onSelected: (_) => setState(() => _fuelType = f),
                    ),
                ],
              ),
            ],
            _sectionTitle(_service == 'tow' ? 'Pickup location' : 'Where are you?'),
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use my current location'),
              onPressed: () async {
                final pos = await currentLatLng();
                if (!context.mounted) return;
                if (pos == null) {
                  showInfo(context,
                      'Location unavailable — allow location access or search below.');
                  return;
                }
                setState(() {
                  _pickedLat = pos.latitude;
                  _pickedLng = pos.longitude;
                  _pickedName = 'My location '
                      '(${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
                  _place.text = _pickedName!;
                  _geoResults = null;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _place,
              onChanged: _onPlaceQuery,
              decoration: InputDecoration(
                labelText: 'Search address or place',
                hintText: 'e.g. Highway 401 near exit 12',
                prefixIcon: const Icon(Icons.place_outlined),
                suffixIcon: located
                    ? const Icon(Icons.check_circle, color: Color(0xFF22C55E))
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_geoResults != null)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _geoResults,
                builder: (context, snap) {
                  final results = snap.data ?? const [];
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))));
                  }
                  if (results.isEmpty) return const SizedBox.shrink();
                  return Card(
                    margin: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        for (final g in results.take(5))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place, size: 18),
                            title: Text(
                                '${g['name'] ?? g['display_name'] ?? g['label'] ?? 'Result'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            onTap: () => _pickGeo(g),
                          ),
                      ],
                    ),
                  );
                },
              ),
            // Live mini-map of the chosen spot.
            if (located)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 150,
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(_pickedLat!, _pickedLng!),
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'ca.okayspace.app',
                          ),
                          MarkerLayer(markers: [
                            Marker(
                              point: LatLng(_pickedLat!, _pickedLng!),
                              width: 36,
                              height: 36,
                              child: const Icon(Icons.location_pin,
                                  color: Color(0xFFEF4444), size: 36),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            TextButton.icon(
              icon: Icon(
                  _manualCoords ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: const Text('Enter coordinates manually'),
              onPressed: () => setState(() => _manualCoords = !_manualCoords),
            ),
            if (_manualCoords)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Latitude',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Longitude',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.check), onPressed: _applyManual),
                ],
              ),
            if (_service == 'tow') ...[
              _sectionTitle('Drop-off location'),
              TextField(
                controller: _drop,
                onChanged: _onDropQuery,
                decoration: InputDecoration(
                  labelText: 'Where should the vehicle go?',
                  hintText: 'e.g. Joe\'s Auto Repair, Mississauga',
                  prefixIcon: const Icon(Icons.flag_outlined),
                  suffixIcon: _dropLat != null
                      ? const Icon(Icons.check_circle,
                          color: Color(0xFF22C55E))
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_dropResults != null)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _dropResults,
                  builder: (context, snap) {
                    final results = snap.data ?? const [];
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))));
                    }
                    if (results.isEmpty) return const SizedBox.shrink();
                    return Card(
                      margin: const EdgeInsets.only(top: 6),
                      child: Column(
                        children: [
                          for (final g in results.take(5))
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place, size: 18),
                              title: Text(
                                  '${g['name'] ?? g['display_name'] ?? g['label'] ?? 'Result'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () => _pickDrop(g),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              // Route preview once both ends are set.
              if (located && _dropLat != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 160,
                      child: IgnorePointer(
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                                (_pickedLat! + _dropLat!) / 2,
                                (_pickedLng! + _dropLng!) / 2),
                            initialZoom: 10,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ca.okayspace.app',
                            ),
                            PolylineLayer(polylines: [
                              Polyline(
                                points: [
                                  LatLng(_pickedLat!, _pickedLng!),
                                  LatLng(_dropLat!, _dropLng!),
                                ],
                                strokeWidth: 3,
                                color: const Color(0xFF008CFF),
                              ),
                            ]),
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(_pickedLat!, _pickedLng!),
                                width: 32,
                                height: 32,
                                alignment: Alignment.topCenter,
                                child: const Icon(Icons.location_pin,
                                    color: Color(0xFFEF4444), size: 32),
                              ),
                              Marker(
                                point: LatLng(_dropLat!, _dropLng!),
                                width: 32,
                                height: 32,
                                alignment: Alignment.topCenter,
                                child: const Icon(Icons.flag,
                                    color: Color(0xFF22C55E), size: 32),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            _sectionTitle('Your vehicle'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _make,
                    decoration: const InputDecoration(
                        labelText: 'Make',
                        hintText: 'Toyota',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _model,
                    decoration: const InputDecoration(
                        labelText: 'Model',
                        hintText: 'Corolla',
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            _sectionTitle('Payment'),
            Wrap(
              spacing: 8,
              children: [
                for (final (id, label, icon) in const [
                  ('wallet', 'Wallet', Icons.account_balance_wallet_outlined),
                  ('cash', 'Cash', Icons.payments_outlined),
                ])
                  ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _payment == id,
                    onSelected: (_) => setState(() => _payment = id),
                  ),
              ],
            ),
            _sectionTitle('Photos (optional)'),
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(_photos[i],
                                width: 84, height: 84, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _photos.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_photos.length < 6)
                    InkWell(
                      onTap: _addPhotos,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.add_a_photo_outlined,
                            color: scheme.outline),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes for the helper (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_priceFor(_service) != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.request_quote_outlined,
                        color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Estimated price: \$${_priceFor(_service)!.toStringAsFixed(2)}'
                        ' — final total may vary',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy || !located || !dropSet ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(!located
                  ? 'Pick a location first'
                  : !dropSet
                      ? 'Pick a drop-off first'
                      : 'Submit request'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
