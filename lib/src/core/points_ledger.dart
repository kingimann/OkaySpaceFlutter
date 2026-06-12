import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A local, on-device tally of point-earning activity.
///
/// The backend stays authoritative for a user's real `points`/`level`, but it
/// exposes no per-source breakdown and no "online time" reward — so this
/// mirror tracks, on this device, which activities the user does most and
/// quietly accrues a *small* bonus for time spent in the app. It powers the
/// "what's earning you points" breakdown and updates listeners live as points
/// are awarded.
class PointsLedger extends ChangeNotifier {
  PointsLedger._() {
    _load();
  }

  /// The app-wide instance.
  static final PointsLedger instance = PointsLedger._();

  static const _key = 'okayspace.points_ledger';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // --- Online-time tuning (deliberately stingy) ---------------------------

  /// Seconds of foreground time that earn a single point.
  static const int secondsPerOnlinePoint = 300; // 5 minutes → 1 point

  /// The most online-time points that can be earned in a single day.
  static const int onlineDailyCap = 10;

  // --- Award amounts for tracked actions ----------------------------------
  static const int postPoints = 5;
  static const int reactionPoints = 1;
  static const int socialPoints = 3;

  // --- State (persisted) --------------------------------------------------
  final Map<String, int> _bySource = {};
  String _onlineDay = '';
  int _onlineLeftoverSeconds = 0; // toward the next online point
  int _onlinePointsToday = 0;

  // Set while the app is in the foreground; null while backgrounded.
  DateTime? _activeSince;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Points tallied per source id (read-only view), e.g. `{'online': 12}`.
  Map<String, int> get bySource => Map.unmodifiable(_bySource);

  /// Total points tracked locally across all sources.
  int get total => _bySource.values.fold(0, (a, b) => a + b);

  /// Online-time points earned so far today.
  int get onlinePointsToday {
    _rolloverIfNeeded();
    return _onlinePointsToday;
  }

  /// How many more online points can still be earned today.
  int get onlineRemainingToday => (onlineDailyCap - onlinePointsToday).clamp(0, onlineDailyCap);

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  void _rolloverIfNeeded() {
    if (_onlineDay != _today) {
      _onlineDay = _today;
      _onlineLeftoverSeconds = 0;
      _onlinePointsToday = 0;
    }
  }

  // --- Persistence --------------------------------------------------------
  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw);
        if (m is Map) {
          final src = m['bySource'];
          if (src is Map) {
            src.forEach((k, v) {
              if (v is num) _bySource['$k'] = v.toInt();
            });
          }
          _onlineDay = (m['onlineDay'] as String?) ?? '';
          _onlineLeftoverSeconds = (m['onlineSeconds'] as num?)?.toInt() ?? 0;
          _onlinePointsToday = (m['onlineToday'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {/* start fresh */}
    _rolloverIfNeeded();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'bySource': _bySource,
          'onlineDay': _onlineDay,
          'onlineSeconds': _onlineLeftoverSeconds,
          'onlineToday': _onlinePointsToday,
        }),
      );
    } catch (_) {/* best effort */}
  }

  // --- Awarding -----------------------------------------------------------

  /// Records [amount] points earned from [source]. Ignored for non-positive
  /// amounts so toggles (e.g. un-liking) never subtract.
  void award(String source, int amount) {
    if (amount <= 0) return;
    _bySource[source] = (_bySource[source] ?? 0) + amount;
    notifyListeners();
    _persist();
  }

  // --- Online-time accrual ------------------------------------------------

  /// Call when the app enters the foreground.
  void noteActive() => _activeSince = DateTime.now();

  /// Call on a timer while foregrounded, and when leaving the foreground, to
  /// bank the elapsed online time as points (slowly, and capped per day).
  void accrue() {
    final since = _activeSince;
    if (since == null) return;
    final now = DateTime.now();
    _activeSince = now;
    final elapsed = now.difference(since).inSeconds;
    if (elapsed <= 0) return;

    _rolloverIfNeeded();
    _onlineLeftoverSeconds += elapsed;

    var gained = 0;
    while (_onlineLeftoverSeconds >= secondsPerOnlinePoint &&
        _onlinePointsToday < onlineDailyCap) {
      _onlineLeftoverSeconds -= secondsPerOnlinePoint;
      _onlinePointsToday += 1;
      gained += 1;
    }
    // At the daily cap, stop hoarding seconds.
    if (_onlinePointsToday >= onlineDailyCap) _onlineLeftoverSeconds = 0;

    if (gained > 0) {
      _bySource['online'] = (_bySource['online'] ?? 0) + gained;
      notifyListeners();
    }
    _persist();
  }

  /// Call when the app leaves the foreground.
  void noteInactive() {
    accrue();
    _activeSince = null;
  }
}

/// Convenience accessor.
final PointsLedger pointsLedger = PointsLedger.instance;
