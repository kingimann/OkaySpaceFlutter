import 'package:flutter/material.dart';

import '../core/points_ledger.dart';
import 'common.dart';
import 'gamification.dart';

/// A board of once-a-day goals. Each shows live progress; completed quests
/// can be claimed for a small bonus, and the board resets at midnight.
class DailyQuestsScreen extends StatelessWidget {
  const DailyQuestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Daily quests')),
      body: AnimatedBuilder(
        animation: pointsLedger,
        builder: (context, _) {
          final quests = kDailyQuests;
          final done = quests
              .where((q) => q.current(pointsLedger) >= q.target)
              .length;
          final allClaimed = quests
              .every((q) => pointsLedger.isQuestClaimed(q.id));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                    const Icon(Icons.task_alt, color: Colors.white, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$done of ${quests.length} done today',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20)),
                          Text(
                              allClaimed
                                  ? 'All rewards claimed — back tomorrow!'
                                  : 'Complete goals to claim bonus points',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final q in quests) _questCard(context, q),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.refresh, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Quests reset every day at midnight.',
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

  Widget _questCard(BuildContext context, DailyQuest q) {
    final scheme = Theme.of(context).colorScheme;
    final current = q.current(pointsLedger).clamp(0, q.target);
    final complete = current >= q.target;
    final claimed = pointsLedger.isQuestClaimed(q.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: claimed
            ? q.color.withValues(alpha: 0.10)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:
            claimed ? Border.all(color: q.color.withValues(alpha: 0.4)) : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: q.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(q.icon, color: q.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(q.description,
                        style:
                            TextStyle(color: scheme.outline, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(context, q, complete, claimed),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: q.target > 0 ? current / q.target : 0,
                    minHeight: 7,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(q.color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$current/${q.target}',
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trailing(
      BuildContext context, DailyQuest q, bool complete, bool claimed) {
    final scheme = Theme.of(context).colorScheme;
    if (claimed) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: q.color, size: 18),
        const SizedBox(width: 4),
        Text('+${q.reward}',
            style: TextStyle(color: q.color, fontWeight: FontWeight.bold)),
      ]);
    }
    if (complete) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: q.color,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: () {
          if (pointsLedger.claimQuest(q.id, q.reward)) {
            showInfo(context, 'Claimed +${q.reward} points');
          }
        },
        child: Text('Claim +${q.reward}'),
      );
    }
    return Text('+${q.reward}',
        style: TextStyle(
            color: scheme.outline, fontWeight: FontWeight.w600, fontSize: 13));
  }
}
