import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'gamification.dart';

/// Achievements: a grid of earnable badges with earned / locked (+ progress)
/// state, computed from the user's points, level, verification and stats.
class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key, required this.user, required this.stats});

  final User user;
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = statsFromUser(user, stats);
    final all = kAchievements;
    final earned = all.where((a) => a.earned(s)).toList();
    final locked = all.where((a) => !a.earned(s)).toList();

    Widget tile(Achievement a, bool isEarned) {
      final color = isEarned ? a.color : scheme.outlineVariant;
      final prog = !isEarned && a.progress != null ? a.progress!(s) : null;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isEarned
              ? a.color.withValues(alpha: 0.10)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: isEarned ? Border.all(color: a.color.withValues(alpha: 0.4)) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (prog != null)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      value: prog,
                      strokeWidth: 3,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                Icon(a.icon, color: color, size: 28),
                if (!isEarned && prog == null)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(Icons.lock, size: 14, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(a.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: isEarned ? null : scheme.outline)),
            const SizedBox(height: 2),
            Text(a.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: scheme.outline)),
          ],
        ),
      );
    }

    Widget grid(List<Achievement> items, bool isEarned) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.82),
          itemCount: items.length,
          itemBuilder: (_, i) => tile(items[i], isEarned),
        );

    return Scaffold(
      appBar: const OkayAppBar(title: Text('Badges')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.emoji_events, color: scheme.primary, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      '${earned.length} of ${all.length} badges earned',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (earned.isNotEmpty) ...[
            const Text('Earned',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            grid(earned, true),
            const SizedBox(height: 20),
          ],
          if (locked.isNotEmpty) ...[
            const Text('Locked',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            grid(locked, false),
          ],
        ],
      ),
    );
  }
}
