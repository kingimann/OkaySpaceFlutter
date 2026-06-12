import 'package:flutter/material.dart';

import '../core/points_ledger.dart';
import 'common.dart';
import 'gamification.dart';

/// A board of week-long goals — bigger targets and bigger rewards than the
/// daily quests. Each shows live progress; completed challenges can be claimed
/// for a bonus, and the board resets every Monday.
class WeeklyChallengesScreen extends StatelessWidget {
  const WeeklyChallengesScreen({super.key});

  /// Whole days until the next Monday reset (1 on Sunday, 7 on Monday).
  static int get _daysUntilReset => 8 - DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Weekly challenges')),
      body: AnimatedBuilder(
        animation: pointsLedger,
        builder: (context, _) {
          final challenges = kWeeklyChallenges;
          final done = challenges
              .where((c) => c.current(pointsLedger) >= c.target)
              .length;
          final allClaimed = challenges
              .every((c) => pointsLedger.isChallengeClaimed(c.id));
          final days = _daysUntilReset;
          const headerColor = Color(0xFFF97316);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [headerColor, darken(headerColor, 0.28)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$done of ${challenges.length} done this week',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20)),
                          Text(
                              allClaimed
                                  ? 'All rewards claimed — new board Monday!'
                                  : 'Complete challenges for bigger bonuses',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$days day${days == 1 ? '' : 's'} left',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final c in challenges) _challengeCard(context, c),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.refresh, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Challenges reset every Monday at midnight.',
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

  Widget _challengeCard(BuildContext context, WeeklyChallenge c) {
    final scheme = Theme.of(context).colorScheme;
    final current = c.current(pointsLedger).clamp(0, c.target);
    final complete = current >= c.target;
    final claimed = pointsLedger.isChallengeClaimed(c.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: claimed
            ? c.color.withValues(alpha: 0.10)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:
            claimed ? Border.all(color: c.color.withValues(alpha: 0.4)) : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(c.icon, color: c.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(c.description,
                        style:
                            TextStyle(color: scheme.outline, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(context, c, complete, claimed),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: c.target > 0 ? current / c.target : 0,
                    minHeight: 7,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(c.color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$current/${c.target}',
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trailing(
      BuildContext context, WeeklyChallenge c, bool complete, bool claimed) {
    final scheme = Theme.of(context).colorScheme;
    if (claimed) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: c.color, size: 18),
        const SizedBox(width: 4),
        Text('+${c.reward}',
            style: TextStyle(color: c.color, fontWeight: FontWeight.bold)),
      ]);
    }
    if (complete) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: c.color,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: () {
          if (pointsLedger.claimChallenge(c.id, c.reward)) {
            showInfo(context, 'Claimed +${c.reward} points');
          }
        },
        child: Text('Claim +${c.reward}'),
      );
    }
    return Text('+${c.reward}',
        style: TextStyle(
            color: scheme.outline, fontWeight: FontWeight.w600, fontSize: 13));
  }
}
