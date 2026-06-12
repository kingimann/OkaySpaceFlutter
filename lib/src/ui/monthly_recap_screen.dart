import 'package:flutter/material.dart';

import '../core/points_ledger.dart';
import 'common.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// A recap of the current calendar month: a heatmap calendar of daily points
/// plus highlights (month total, active days, best day, daily average).
class MonthlyRecapScreen extends StatelessWidget {
  const MonthlyRecapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('This month')),
      body: AnimatedBuilder(
        animation: pointsLedger,
        builder: (context, _) {
          final now = DateTime.now();
          final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
          final days = [
            for (var d = 1; d <= daysInMonth; d++)
              (
                day: DateTime(now.year, now.month, d),
                points: pointsLedger.pointsOn(DateTime(now.year, now.month, d)),
              ),
          ];
          final monthTotal = days.fold<int>(0, (a, e) => a + e.points);
          final maxPoints =
              days.fold<int>(0, (m, e) => e.points > m ? e.points : m);
          final activeDays = days.where((e) => e.points > 0).length;
          final best = days.reduce((a, b) => b.points > a.points ? b : a);
          final avg = now.day > 0 ? (monthTotal / now.day).round() : 0;

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
                    const Icon(Icons.calendar_month_outlined,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$monthTotal points',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22)),
                          Text('earned in ${_monthNames[now.month - 1]}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Heatmap calendar.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final l in _weekdayLabels)
                          Expanded(
                            child: Center(
                              child: Text(l,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.outline,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _calendarGrid(context, days, maxPoints, now),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('less',
                            style: TextStyle(
                                fontSize: 10, color: scheme.outline)),
                        const SizedBox(width: 6),
                        for (final a in [0.12, 0.35, 0.6, 0.85])
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: a),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        const SizedBox(width: 2),
                        Text('more',
                            style: TextStyle(
                                fontSize: 10, color: scheme.outline)),
                      ],
                    ),
                  ],
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
                        value: '$activeDays / ${now.day}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stat(context,
                        icon: Icons.speed_outlined,
                        label: 'Daily average',
                        value: '$avg pts'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (best.points > 0)
                _stat(context,
                    icon: Icons.emoji_events_outlined,
                    label: 'Best day this month',
                    value:
                        '${_monthNames[now.month - 1].substring(0, 3)} ${best.day.day} · ${best.points} pts'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Based on activity tracked on this device this month.',
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

  /// Lays the month out as Monday-first weeks of heatmap cells.
  Widget _calendarGrid(
      BuildContext context,
      List<({DateTime day, int points})> days,
      int maxPoints,
      DateTime now) {
    final cells = <Widget>[
      // Blank cells before the 1st so weekdays line up.
      for (var i = 1; i < days.first.day.weekday; i++) const SizedBox(),
      for (final e in days) _dayCell(context, e, maxPoints, now),
    ];
    // Pad the final week to a full row.
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }

    return Column(
      children: [
        for (var row = 0; row < cells.length ~/ 7; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: cells[row * 7 + col],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, ({DateTime day, int points}) e,
      int maxPoints, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = e.day.day == now.day;
    final isFuture = e.day.day > now.day;
    final frac = maxPoints > 0 ? e.points / maxPoints : 0.0;
    final color = isFuture
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
        : e.points == 0
            ? scheme.surfaceContainerHighest
            : scheme.primary.withValues(alpha: (0.15 + 0.7 * frac).clamp(0.15, 0.85));

    return Tooltip(
      message: isFuture ? '' : '${e.day.day}: ${e.points} pts',
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: isToday ? Border.all(color: scheme.primary, width: 2) : null,
        ),
        child: Center(
          child: Text('${e.day.day}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: isFuture
                    ? scheme.outlineVariant
                    : frac > 0.45
                        ? Colors.white
                        : scheme.outline,
              )),
        ),
      ),
    );
  }

  Widget _stat(BuildContext context,
      {required IconData icon, required String label, required String value}) {
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
}
