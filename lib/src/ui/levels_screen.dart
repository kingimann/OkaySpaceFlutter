import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import '../core/points_ledger.dart';
import 'common.dart';
import 'daily_quests_screen.dart';
import 'gamification.dart';
import 'points_breakdown_screen.dart';
import 'profile_decor.dart';
import 'rewards_screen.dart';
import 'weekly_recap_screen.dart';

/// Points & Levels: current standing, progress to the next level, the tier
/// ladder, and how points are earned.
class LevelsScreen extends StatelessWidget {
  const LevelsScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tier = tierForLevel(user.level);
    final next = nextTierAfter(user.level);
    final toNextRaw = user.raw['points_to_next'] ?? user.raw['pts_to_next'];
    final toNext = toNextRaw is num ? toNextRaw.toInt() : null;
    final progress = (toNext != null && (user.points + toNext) > 0)
        ? user.points / (user.points + toNext)
        : (user.points % 100) / 100;

    return Scaffold(
      appBar: const OkayAppBar(title: Text('Points & Levels')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current standing card.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tier.color, darken(tier.color, 0.28)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(tier.icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Text('Level ${user.level} · ${user.levelTitle}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${user.points} points',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                    toNext != null
                        ? '$toNext points to level ${user.level + 1}'
                        : 'Keep earning to level up',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Daily activity streak (local).
          AnimatedBuilder(
            animation: pointsLedger,
            builder: (context, _) {
              final streak = pointsLedger.currentStreak;
              final longest = pointsLedger.longestStreak;
              const flame = Color(0xFFF59E0B);
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: flame.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: flame.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: flame, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              streak <= 1
                                  ? 'Day 1 streak'
                                  : '$streak-day streak',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(
                              streak <= 1
                                  ? 'Come back tomorrow to keep it going'
                                  : 'Best: $longest days · keep it alive for a daily bonus',
                              style:
                                  TextStyle(color: scheme.outline, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Daily quests entry.
          AnimatedBuilder(
            animation: pointsLedger,
            builder: (context, _) {
              final done = kDailyQuests
                  .where((q) => q.current(pointsLedger) >= q.target)
                  .length;
              return Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DailyQuestsScreen())),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.task_alt_outlined, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Daily quests',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text('$done of ${kDailyQuests.length} done today',
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 12)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.outline),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Weekly recap entry.
          AnimatedBuilder(
            animation: pointsLedger,
            builder: (context, _) {
              final week = pointsLedger.pointsThisWeek;
              return Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const WeeklyRecapScreen())),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Weekly recap',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text('$week points in the last 7 days',
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 12)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.outline),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Cosmetic rewards unlocked by level.
          Builder(builder: (context) {
            final unlocked = kAvatarFrames
                    .where((f) => frameUnlockLevel(f.id) <= user.level)
                    .length +
                kProfileBackgrounds
                    .where((b) => backgroundUnlockLevel(b.id) <= user.level)
                    .length;
            final total = kAvatarFrames.length + kProfileBackgrounds.length;
            return Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RewardsScreen(user: user))),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.card_giftcard, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Rewards',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            Text('$unlocked of $total cosmetics unlocked',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.outline),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // Live entry into the per-activity points breakdown.
          AnimatedBuilder(
            animation: pointsLedger,
            builder: (context, _) {
              final online = pointsLedger.onlinePointsToday;
              return Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PointsBreakdownScreen())),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.insights, color: scheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("What's earning you points",
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                  online > 0
                                      ? '+$online from online time today · tap to see the breakdown'
                                      : 'See which activities earn you the most',
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 12)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: scheme.outline),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (next != null)
            Text('Next tier: ${next.name} at level ${next.minLevel}',
                style: TextStyle(color: scheme.outline)),
          const SizedBox(height: 8),
          const Text('Tiers',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          for (final t in kPointsTiers)
            Builder(builder: (context) {
              final reached = user.level >= t.minLevel;
              final current = tier.name == t.name;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: current
                      ? t.color.withValues(alpha: 0.15)
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: current
                      ? Border.all(color: t.color, width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(t.icon,
                        color: reached ? t.color : scheme.outlineVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(t.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: reached ? null : scheme.outline)),
                    ),
                    if (current)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: t.color,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Text('You',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      )
                    else
                      Text('Lv ${t.minLevel}',
                          style: TextStyle(color: scheme.outline, fontSize: 12)),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          const Text('How to earn points',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          for (final (icon, title, sub) in kPointWays)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: scheme.primary),
              title: Text(title),
              subtitle: Text(sub),
            ),
        ],
      ),
    );
  }
}
