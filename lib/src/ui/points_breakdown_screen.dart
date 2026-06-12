import 'package:flutter/material.dart';

import '../core/points_ledger.dart';
import 'common.dart';
import 'gamification.dart';

/// "What's earning you points": a live, ranked breakdown of the point-earning
/// activity tracked on this device, plus today's online-time bonus progress.
class PointsBreakdownScreen extends StatelessWidget {
  const PointsBreakdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text("What's earning you points")),
      body: AnimatedBuilder(
        animation: pointsLedger,
        builder: (context, _) {
          final totals = pointsLedger.bySource;
          final total = pointsLedger.total;
          // Sources ranked by points earned, biggest first.
          final entries = totals.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final onlineToday = pointsLedger.onlinePointsToday;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Total tracked.
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
                    const Icon(Icons.insights, color: Colors.white, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$total points',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22)),
                          const Text('tracked from your activity here',
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Online-time bonus today.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Online time today',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Text('$onlineToday / ${PointsLedger.onlineDailyCap}',
                            style: TextStyle(
                                color: scheme.outline,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (onlineToday / PointsLedger.onlineDailyCap)
                            .clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        onlineToday >= PointsLedger.onlineDailyCap
                            ? "You've earned today's full online bonus — come back tomorrow."
                            : 'Earns 1 point for every '
                                '${PointsLedger.secondsPerOnlinePoint ~/ 60} minutes in the app, '
                                'up to ${PointsLedger.onlineDailyCap} a day.',
                        style: TextStyle(color: scheme.outline, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const Text('By activity',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.bubble_chart_outlined,
                          size: 48, color: scheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                          'No activity yet. Post, react and connect — '
                          'and just being here earns a little.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.outline)),
                    ],
                  ),
                )
              else
                for (final e in entries)
                  _sourceRow(context, pointSourceFor(e.key), e.value, total),

              // Recent activity timeline.
              if (pointsLedger.recentEvents.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Recent',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                for (final ev in pointsLedger.recentEvents.take(15))
                  _eventRow(context, ev),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Tracked on this device to show what you do most. '
                        'Your official points and level come from OkaySpace.',
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

  Widget _sourceRow(
      BuildContext context, PointSource src, int points, int total) {
    final scheme = Theme.of(context).colorScheme;
    final frac = total > 0 ? points / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: src.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(src.icon, color: src.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(src.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text('$points pts',
                        style: TextStyle(
                            color: src.color, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: frac.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(src.color),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(frac * 100).round()}% of tracked points',
                    style: TextStyle(color: scheme.outline, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(BuildContext context, PointEvent ev) {
    final scheme = Theme.of(context).colorScheme;
    final src = pointSourceFor(ev.source);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(src.icon, color: src.color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(src.label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(shortAgo(ev.at),
              style: TextStyle(color: scheme.outline, fontSize: 12)),
          const SizedBox(width: 12),
          Text('+${ev.amount}',
              style:
                  TextStyle(color: src.color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
