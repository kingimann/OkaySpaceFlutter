import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/device_location.dart';
import '../core/mapbox_api.dart';
import '../core/tts.dart';

/// Live, in-app turn-by-turn navigation ("Go"): follows the device location,
/// advances the maneuver as you reach each turn, speaks guidance (web), and
/// re-routes when you leave the line. A best-effort experience — it degrades
/// gracefully when GPS is sparse.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.line,
    required this.steps,
    required this.destination,
    this.destName,
  });

  final List<LatLng> line;
  final List<RouteStep> steps;
  final LatLng destination;
  final String? destName;

  static Future<void> open(
    BuildContext context, {
    required List<LatLng> line,
    required List<RouteStep> steps,
    required LatLng destination,
    String? destName,
  }) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NavigationScreen(
            line: line,
            steps: steps,
            destination: destination,
            destName: destName),
      ));

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const _distance = Distance();
  final _controller = MapController();
  StreamSubscription<GeoFix>? _sub;

  late List<LatLng> _route = widget.line;
  late List<RouteStep> _steps = widget.steps;
  // Index of the maneuver we're heading toward (the next turn).
  late int _step = _steps.length > 1 ? 1 : 0;

  LatLng? _pos;
  double _heading = 0;
  double _speedKmh = 0;
  bool _mapReady = false;
  bool _arrived = false;
  bool _rerouting = false;
  bool _muted = false;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  int? _spokenStep;

  void _say(String text) {
    if (!_muted) speak(text);
  }

  @override
  void initState() {
    super.initState();
    final first = widget.steps.isNotEmpty ? widget.steps.first.instruction : '';
    _say(first.isEmpty ? 'Starting navigation' : 'Starting. $first');
    _sub = fixStream().listen(_onFix);
  }

  @override
  void dispose() {
    _sub?.cancel();
    stopSpeaking();
    _controller.dispose();
    super.dispose();
  }

  void _onFix(GeoFix fix) {
    if (!mounted) return;
    _pos = fix.point;
    _heading = fix.heading;
    _speedKmh = fix.speedKmh;
    if (_mapReady) _controller.move(fix.point, 16.5);

    // Advance past any maneuvers we've reached.
    while (_step < _steps.length - 1) {
      final loc = _steps[_step].location;
      if (loc != null && _distance(fix.point, loc) < 25) {
        _step++;
        _spokenStep = null;
      } else {
        break;
      }
    }

    // Arrival.
    if (!_arrived && _distance(fix.point, widget.destination) < 30) {
      _arrived = true;
      _say('You have arrived${widget.destName != null ? ' at ${widget.destName}' : ''}.');
    }

    // Voice the upcoming maneuver once we're close (or immediately after a turn).
    if (_step < _steps.length && _spokenStep != _step) {
      final cur = _steps[_step];
      final d = cur.location != null ? _distance(fix.point, cur.location!) : 0.0;
      if (d < 250) {
        final say = cur.instruction.isEmpty ? 'Continue' : cur.instruction;
        _say(say);
        _spokenStep = _step;
      }
    }

    // Off-route detection → re-route (throttled).
    if (!_rerouting && _route.isNotEmpty) {
      var minD = double.infinity;
      for (final p in _route) {
        final dd = _distance(fix.point, p);
        if (dd < minD) minD = dd;
      }
      if (minD > 60 &&
          DateTime.now().difference(_lastReroute).inSeconds > 8) {
        _reroute();
      }
    }
    setState(() {});
  }

  Future<void> _reroute() async {
    final from = _pos;
    if (_rerouting || from == null || !hasMapbox) return;
    _rerouting = true;
    _lastReroute = DateTime.now();
    _say('Re-routing');
    try {
      final r = await driveRoute([from, widget.destination]);
      if (mounted && r != null && r.line.length >= 2) {
        setState(() {
          _route = r.line;
          _steps = r.steps;
          _step = _steps.length > 1 ? 1 : 0;
          _spokenStep = null;
        });
      }
    } catch (_) {/* keep the old route on failure */} finally {
      _rerouting = false;
    }
  }

  /// Metres remaining to the destination, summed over the steps still ahead.
  double get _remainingMeters {
    var m = 0.0;
    for (var i = _step; i < _steps.length; i++) {
      m += _steps[i].meters;
    }
    // No usable steps → straight-line estimate.
    if (m == 0 && _pos != null) m = _distance(_pos!, widget.destination);
    return m;
  }

  String _fmt(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} km'
      : '${metres.round()} m';

  IconData _icon(RouteStep s) {
    if (s.type == 'arrive') return Icons.flag;
    if (s.type == 'depart') return Icons.trip_origin;
    if (s.type == 'roundabout' || s.type == 'rotary') return Icons.rotate_right;
    if (s.modifier.contains('uturn')) return Icons.u_turn_left;
    if (s.modifier.contains('left')) return Icons.turn_left;
    if (s.modifier.contains('right')) return Icons.turn_right;
    return Icons.straight;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cur = (_step < _steps.length) ? _steps[_step] : null;
    final next = (_step + 1 < _steps.length) ? _steps[_step + 1] : null;
    final toTurn = (cur?.location != null && _pos != null)
        ? _distance(_pos!, cur!.location!)
        : null;
    final remaining = _remainingMeters;
    final etaMin =
        (remaining / 1000 / (_speedKmh > 8 ? _speedKmh : 40) * 60).round();

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _pos ??
                  (widget.line.isNotEmpty ? widget.line.first : widget.destination),
              initialZoom: 16.5,
              onMapReady: () => _mapReady = true,
            ),
            children: [
              mapboxTileLayer(),
              PolylineLayer(polylines: [
                Polyline(
                    points: _route,
                    strokeWidth: 7,
                    color: const Color(0xFF2563EB)),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: widget.destination,
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.flag, color: Color(0xFFEF4444), size: 30),
                ),
                if (_pos != null)
                  Marker(
                    point: _pos!,
                    width: 34,
                    height: 34,
                    child: Transform.rotate(
                      angle: _heading * 3.1415926 / 180,
                      child: const Icon(Icons.navigation,
                          color: Color(0xFF2563EB), size: 30),
                    ),
                  ),
              ]),
            ],
          ),

          // Maneuver banner.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2430),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 12),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(cur != null ? _icon(cur) : Icons.navigation,
                        color: Colors.white, size: 38),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (toTurn != null)
                            Text('In ${_fmt(toTurn)}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          Text(
                            _arrived
                                ? 'You have arrived'
                                : (cur?.instruction.isNotEmpty == true
                                    ? cur!.instruction
                                    : 'Continue'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                          if (!_arrived &&
                              next != null &&
                              next.instruction.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(_icon(next),
                                      color: Colors.white54, size: 16),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text('Then ${next.instruction}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom bar: ETA / distance + End.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _arrived ? 'Arrived' : '~$etaMin min · ${_fmt(remaining)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          if (_rerouting)
                            Text('Re-routing…',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up_outlined),
                      tooltip: _muted ? 'Unmute voice' : 'Mute voice',
                      onPressed: () {
                        setState(() => _muted = !_muted);
                        if (_muted) stopSpeaking();
                      },
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError),
                      icon: const Icon(Icons.close),
                      label: const Text('End'),
                      onPressed: () => Navigator.of(context).pop(),
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
}
