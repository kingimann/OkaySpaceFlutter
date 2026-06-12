import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A single point-earning event, newest-first in [PointsLedger.recentEvents].
class PointEvent {
  const PointEvent(this.source, this.amount, this.at);
  final String source;
  final int amount;
  final DateTime at;
}

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

  /// The most a single day's streak bonus can be worth.
  static const int streakDailyCap = 7;

  /// How many recent point events to keep for the activity log.
  static const int _maxEvents = 60;

  // --- State (persisted) --------------------------------------------------
  final Map<String, int> _bySource = {};
  // Recent point events, newest last (kept ≤ _maxEvents).
  final List<PointEvent> _events = [];
  String _onlineDay = '';
  int _onlineLeftoverSeconds = 0; // toward the next online point
  int _onlinePointsToday = 0;

  // Daily activity streak.
  String _lastActiveDay = '';
  int _currentStreak = 0;
  int _longestStreak = 0;

  // Per-day action counts (reset each day, keyed by source) and the ids of
  // daily quests already claimed today — both scoped to [_onlineDay].
  final Map<String, int> _dailyActions = {};
  final Set<String> _claimedQuests = {};

  // Set while the app is in the foreground; null while backgrounded.
  DateTime? _activeSince;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Points tallied per source id (read-only view), e.g. `{'online': 12}`.
  Map<String, int> get bySource => Map.unmodifiable(_bySource);

  /// Recent point events, newest first.
  List<PointEvent> get recentEvents => _events.reversed.toList(growable: false);

  /// Adds [amount] to [source]'s total and records an event. Caller notifies.
  void _credit(String source, int amount) {
    _bySource[source] = (_bySource[source] ?? 0) + amount;
    _events.add(PointEvent(source, amount, DateTime.now()));
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
  }

  /// Total points tracked locally across all sources.
  int get total => _bySource.values.fold(0, (a, b) => a + b);

  /// Online-time points earned so far today.
  int get onlinePointsToday {
    _rolloverIfNeeded();
    return _onlinePointsToday;
  }

  /// How many more online points can still be earned today.
  int get onlineRemainingToday => (onlineDailyCap - onlinePointsToday).clamp(0, onlineDailyCap);

  /// Consecutive days the app has been opened (today counted once seen).
  int get currentStreak => _currentStreak;

  /// The best streak ever reached.
  int get longestStreak => _longestStreak;

  /// Whether today has already been counted toward the streak.
  bool get countedToday => _lastActiveDay == _today;

  String _dayKey(DateTime n) =>
      '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';

  String get _today => _dayKey(DateTime.now());

  void _rolloverIfNeeded() {
    if (_onlineDay != _today) {
      _onlineDay = _today;
      _onlineLeftoverSeconds = 0;
      _onlinePointsToday = 0;
      _dailyActions.clear();
      _claimedQuests.clear();
    }
  }

  /// How many times [source] was awarded today (e.g. posts/reactions made).
  int actionsToday(String source) {
    _rolloverIfNeeded();
    return _dailyActions[source] ?? 0;
  }

  /// Whether a daily quest has already been claimed today.
  bool isQuestClaimed(String questId) {
    _rolloverIfNeeded();
    return _claimedQuests.contains(questId);
  }

  /// Claims a completed daily quest's reward (once per day). Returns true if
  /// the reward was granted now.
  bool claimQuest(String questId, int reward) {
    _rolloverIfNeeded();
    if (_claimedQuests.contains(questId) || reward <= 0) return false;
    _claimedQuests.add(questId);
    award('quests', reward);
    return true;
  }

  /// Counts today toward the daily streak (once), extending or resetting it,
  /// and awards a small streak bonus that grows with the run (capped per day).
  void _touchStreak() {
    final today = _today;
    if (_lastActiveDay == today) return; // already counted today

    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    if (_lastActiveDay == yesterday) {
      _currentStreak += 1; // kept the run going
    } else {
      _currentStreak = 1; // first day, or the run lapsed
    }
    _lastActiveDay = today;
    if (_currentStreak > _longestStreak) _longestStreak = _currentStreak;

    // Bonus grows with the streak but is capped so it stays modest.
    final bonus = _currentStreak.clamp(1, streakDailyCap);
    _credit('streak', bonus);

    notifyListeners();
    _persist();
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
          _lastActiveDay = (m['lastActiveDay'] as String?) ?? '';
          _currentStreak = (m['currentStreak'] as num?)?.toInt() ?? 0;
          _longestStreak = (m['longestStreak'] as num?)?.toInt() ?? 0;
          final da = m['dailyActions'];
          if (da is Map) {
            da.forEach((k, v) {
              if (v is num) _dailyActions['$k'] = v.toInt();
            });
          }
          final cq = m['claimedQuests'];
          if (cq is List) {
            _claimedQuests.addAll(cq.whereType<String>());
          }
          final evts = m['events'];
          if (evts is List) {
            for (final e in evts) {
              if (e is Map && e['s'] is String && e['a'] is num && e['t'] is num) {
                _events.add(PointEvent(
                  e['s'] as String,
                  (e['a'] as num).toInt(),
                  DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt()),
                ));
              }
            }
          }
        }
      }
    } catch (_) {/* start fresh */}
    _rolloverIfNeeded();
    _loaded = true;
    _touchStreak(); // count this session's day once persisted state is known
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
          'lastActiveDay': _lastActiveDay,
          'currentStreak': _currentStreak,
          'longestStreak': _longestStreak,
          'dailyActions': _dailyActions,
          'claimedQuests': _claimedQuests.toList(),
          'events': [
            for (final e in _events)
              {'s': e.source, 'a': e.amount, 't': e.at.millisecondsSinceEpoch},
          ],
        }),
      );
    } catch (_) {/* best effort */}
  }

  // --- Awarding -----------------------------------------------------------

  /// Records [amount] points earned from [source]. Ignored for non-positive
  /// amounts so toggles (e.g. un-liking) never subtract.
  void award(String source, int amount) {
    if (amount <= 0) return;
    _rolloverIfNeeded();
    _dailyActions[source] = (_dailyActions[source] ?? 0) + 1;
    _credit(source, amount);
    notifyListeners();
    _persist();
  }

  // --- Online-time accrual ------------------------------------------------

  /// Call when the app enters the foreground.
  void noteActive() {
    _activeSince = DateTime.now();
    // After load, a resume that crosses midnight should still count the day.
    if (_loaded) _touchStreak();
  }

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
      _credit('online', gained);
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
