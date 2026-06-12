import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/points_ledger.dart';
import 'common.dart';
import 'gamification.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Personal records: the user's all-time bests from locally-tracked points —
/// best day, biggest single gain, longest streak, days active, and lifetime
/// quest/challenge claims.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Personal records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share records',
            onPressed: () => _shareRecords(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: pointsLedger,
        builder: (context, _) {
          final l = pointsLedger;
          final topSource = _topSource(l);
          const gold = Color(0xFFEAB308);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [gold, darken(gold, 0.3)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${l.total} points',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22)),
                          const Text('tracked on this device, all time',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _record(context,
                        icon: Icons.whatshot_outlined,
                        color: const Color(0xFFF59E0B),
                        label: 'Best day',
                        value: l.bestDayPoints > 0
                            ? '${l.bestDayPoints} pts'
                            : '—',
                        sub: _prettyDay(l.bestDayDate)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _record(context,
                        icon: Icons.bolt_outlined,
                        color: const Color(0xFF8B5CF6),
                        label: 'Biggest gain',
                        value: l.biggestGain > 0 ? '+${l.biggestGain}' : '—',
                        sub: l.biggestGainSource.isEmpty
                            ? null
                            : pointSourceFor(l.biggestGainSource).label),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _record(context,
                        icon: Icons.local_fire_department,
                        color: const Color(0xFFEF4444),
                        label: 'Longest streak',
                        value: '${l.longestStreak}d',
                        sub: l.currentStreak > 0
                            ? 'current: ${l.currentStreak}d'
                            : null),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _record(context,
                        icon: Icons.event_available_outlined,
                        color: const Color(0xFF22C55E),
                        label: 'Days active',
                        value: '${l.daysActive}',
                        sub: l.daysActive == 1 ? 'day' : 'days'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _record(context,
                        icon: Icons.task_alt_outlined,
                        color: const Color(0xFF06B6D4),
                        label: 'Quests claimed',
                        value: '${l.questsClaimedTotal}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _record(context,
                        icon: Icons.flag_outlined,
                        color: const Color(0xFFF97316),
                        label: 'Challenges claimed',
                        value: '${l.challengesClaimedTotal}'),
                  ),
                ],
              ),
              if (topSource != null) ...[
                const SizedBox(height: 12),
                _record(context,
                    icon: topSource.icon,
                    color: topSource.color,
                    label: 'Top point source',
                    value: topSource.label,
                    sub: '${pointsLedger.bySource[topSource.id]} pts all time'),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Records are based on activity tracked on this device.',
                        style: TextStyle(color: scheme.outline, fontSize: 12)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// The point source with the highest all-time total, or null if none yet.
  PointSource? _topSource(PointsLedger l) {
    String? id;
    var best = 0;
    l.bySource.forEach((k, v) {
      if (v > best) {
        best = v;
        id = k;
      }
    });
    return id == null ? null : pointSourceFor(id!);
  }

  /// 'yyyy-mm-dd' → 'Jun 12', or null if blank/unparseable.
  String? _prettyDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (m == null || d == null || m < 1 || m > 12) return null;
    return '${_months[m - 1]} $d';
  }

  Widget _record(BuildContext context,
      {required IconData icon,
      required Color color,
      required String label,
      required String value,
      String? sub}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          Text(label, style: TextStyle(color: scheme.outline, fontSize: 12)),
          if (sub != null)
            Text(sub,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Copies a shareable summary of the user's records to the clipboard.
  void _shareRecords(BuildContext context) {
    final l = pointsLedger;
    final parts = <String>[
      'My OkaySpace records 🏆',
      '${l.total} points all time',
      if (l.bestDayPoints > 0) '⚡ best day: ${l.bestDayPoints} pts',
      if (l.longestStreak > 1) '🔥 longest streak: ${l.longestStreak} days',
      if (l.daysActive > 0) '📅 ${l.daysActive} days active',
    ];
    Clipboard.setData(ClipboardData(text: parts.join(' · ')));
    showInfo(context, 'Records copied to share');
  }
}
