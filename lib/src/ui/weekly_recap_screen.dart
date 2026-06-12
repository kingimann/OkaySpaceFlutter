import 'package:flutter/material.dart';

import '../core/points_ledger.dart';
import 'common.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// A 7-day recap of locally-tracked points: a daily bar chart plus highlights
/// (week total, best day, active days, current streak).
class WeeklyRecapScreen extends StatelessWidget {
  const WeeklyRecapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Weekly recap')),
      body: AnimatedBuilder(
        animation: pointsLedger,
        builder: (context, _) {
          final days = pointsLedger.last7Days();
          final weekTotal = pointsLedger.pointsThisWeek;
          final maxPoints =
              days.fold<int>(0, (m, e) => e.points > m ? e.points : m);
          final activeDays = days.where((e) => e.points > 0).length;
          final best = days.isEmpty
              ? null
              : days.reduce((a, b) => b.points > a.points ? b : a);
          final today = DateTime.now();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Headline total.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, darken(scheme.primary, 0.28)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$weekTotal points',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22)),
                          const Text('earned in the last 7 days',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Daily bar chart.
              Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final e in days)
                        Expanded(
                          child: _bar(
                            context,
                            points: e.points,
                            maxPoints: maxPoints,
                            label: _weekdayLabels[(e.day.weekday - 1) % 7],
                            isToday: e.day.year == today.year &&
                                e.day.month == today.month &&
                                e.day.day == today.day,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Highlights.
              Row(
                children: [
                  Expanded(
                    child: _stat(context,
                        icon: Icons.event_available_outlined,
                        label: 'Active days',
                        value: '$activeDays / 7'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stat(context,
                        icon: Icons.local_fire_department,
                        label: 'Current streak',
                        value: '${pointsLedger.currentStreak}d'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (best != null && best.points > 0)
                _stat(context,
                    icon: Icons.emoji_events_outlined,
                    label: 'Best day',
                    value:
                        '${_fullWeekday(best.day.weekday)} · ${best.points} pts',
                    wide: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Based on activity tracked on this device over the last week.',
                        style:
                            TextStyle(color: scheme.outline, fontSize: 12)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(BuildContext context,
      {required int points,
      required int maxPoints,
      required String label,
      required bool isToday}) {
    final scheme = Theme.of(context).colorScheme;
    final frac = maxPoints > 0 ? points / maxPoints : 0.0;
    final color = isToday ? scheme.primary : scheme.primary.withValues(alpha: 0.45);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(points > 0 ? '$points' : '',
            style: TextStyle(
                fontSize: 10,
                color: scheme.outline,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        // 96px of headroom for bars; min height keeps empty days visible.
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: (96 * frac).clamp(4.0, 96.0),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: isToday ? scheme.primary : scheme.outline,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }

  Widget _stat(BuildContext context,
      {required IconData icon,
      required String label,
      required String value,
      bool wide = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fullWeekday(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][(weekday - 1) % 7];
}
