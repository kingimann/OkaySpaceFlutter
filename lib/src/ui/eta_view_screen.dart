import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/mapbox_api.dart';
import '../models/json.dart';
import 'common.dart';

/// Live, read-only viewer for a shared ETA (the recipient side of "Share my
/// ETA"). Polls the public endpoint so the sharer's position and ETA update as
/// they travel; stops once the share ends or expires.
class EtaViewScreen extends StatefulWidget {
  const EtaViewScreen({super.key, required this.shareId});

  final String shareId;

  static Future<void> open(BuildContext context, String shareId) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EtaViewScreen(shareId: shareId),
      ));

  @override
  State<EtaViewScreen> createState() => _EtaViewScreenState();
}

class _EtaViewScreenState extends State<EtaViewScreen> {
  final _controller = MapController();
  Timer? _poll;
  Map<String, dynamic>? _share;
  Object? _error;
  bool _loading = true;
  bool _firstFix = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Mirror the sharer's ~10s push cadence.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await api.roadside.publicEta(widget.shareId);
      if (!mounted) return;
      setState(() {
        _share = s;
        _error = null;
        _loading = false;
      });
      // Once the share is inactive, stop polling — nothing more will change.
      if (s['active'] == false) _poll?.cancel();
      final cur = _current;
      if (cur != null && _firstFix) {
        _firstFix = false;
        _controller.move(cur, 14);
      } else if (cur != null) {
        _controller.move(cur, _controller.camera.zoom);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  LatLng? get _current {
    final s = _share;
    if (s == null) return null;
    final lat = asDoubleOrNull(s['current_latitude']);
    final lng = asDoubleOrNull(s['current_longitude']);
    return (lat != null && lng != null) ? LatLng(lat, lng) : null;
  }

  LatLng? get _destination {
    final s = _share;
    if (s == null) return null;
    final lat = asDoubleOrNull(s['destination_latitude']);
    final lng = asDoubleOrNull(s['destination_longitude']);
    return (lat != null && lng != null) ? LatLng(lat, lng) : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = _share;
    final name = s == null ? 'Shared ETA' : asString(s['name'], 'Shared ETA');
    final active = s?['active'] != false;
    final cur = _current;
    final dest = _destination;

    return Scaffold(
      appBar: OkayAppBar(title: Text(name)),
      body: _error != null && s == null
          ? CenteredMessage(
              message: messageFor(_error),
              icon: Icons.error_outline,
              onRetry: _refresh,
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _controller,
                      options: MapOptions(
                        initialCenter: cur ?? dest ?? const LatLng(0, 0),
                        initialZoom: 13,
                      ),
                      children: [
                        mapboxTileLayer(),
                        if (cur != null && dest != null)
                          PolylineLayer(polylines: [
                            Polyline(
                              points: [cur, dest],
                              strokeWidth: 4,
                              color: const Color(0xFF2563EB),
                            ),
                          ]),
                        MarkerLayer(markers: [
                          if (dest != null)
                            Marker(
                              point: dest,
                              width: 36,
                              height: 36,
                              child: const Icon(Icons.flag,
                                  color: Color(0xFFEF4444), size: 30),
                            ),
                          if (cur != null)
                            Marker(
                              point: cur,
                              width: 30,
                              height: 30,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active
                                      ? const Color(0xFF2563EB)
                                      : Theme.of(context).colorScheme.outline,
                                  border:
                                      Border.all(color: Colors.white, width: 3),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Colors.black26, blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 16,
                      child: _statusCard(s, active),
                    ),
                  ],
                ),
    );
  }

  Widget _statusCard(Map<String, dynamic>? s, bool active) {
    final scheme = Theme.of(context).colorScheme;
    final etaMin = s == null ? null : asIntOrNull(s['eta_minutes']);
    final destName = s == null ? null : asStringOrNull(s['destination_name']);
    final updated = s == null ? null : asDateOrNull(s['updated_at']);

    final String headline;
    if (!active) {
      headline = 'Sharing has ended';
    } else if (etaMin != null) {
      headline = etaMin <= 0 ? 'Arriving now' : 'Arriving in $etaMin min';
    } else {
      headline = 'On the way';
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(active ? Icons.navigation : Icons.flag_circle,
                    color: active ? const Color(0xFF2563EB) : scheme.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(headline,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
            if (destName != null && destName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('To $destName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.outline)),
            ],
            if (updated != null) ...[
              const SizedBox(height: 4),
              Text(
                active
                    ? 'Updated ${shortAgo(updated)}'
                    : 'Last seen ${shortAgo(updated)}',
                style: TextStyle(color: scheme.outline, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
