import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'gamification.dart';
import 'levels_screen.dart';

/// Shows a celebratory dialog when the user's level increases. Calls out a new
/// tier when one is reached. Dependency-free: a scaling burst of sparkles
/// around the tier emblem.
void showLevelUpCelebration(
  BuildContext context, {
  required int oldLevel,
  required int newLevel,
  required User user,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _LevelUpDialog(
      oldLevel: oldLevel,
      newLevel: newLevel,
      user: user,
    ),
  );
}

class _LevelUpDialog extends StatefulWidget {
  const _LevelUpDialog({
    required this.oldLevel,
    required this.newLevel,
    required this.user,
  });

  final int oldLevel;
  final int newLevel;
  final User user;

  @override
  State<_LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<_LevelUpDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = tierForLevel(widget.newLevel);
    final prevTier = tierForLevel(widget.oldLevel);
    final newTier = tier.name != prevTier.name;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sparkle burst around the tier emblem.
            SizedBox(
              width: 140,
              height: 140,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(_c.value);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < 8; i++)
                        _sparkle(i, t, tier.color),
                      Transform.scale(
                        scale: Curves.elasticOut
                            .transform(_c.value.clamp(0.0, 1.0)),
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [tier.color, darken(tier.color, 0.28)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: tier.color.withValues(alpha: 0.5),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(tier.icon, color: Colors.white, size: 46),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(newTier ? 'New tier unlocked!' : 'Level up!',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 22)),
            const SizedBox(height: 4),
            Text('You reached level ${widget.newLevel}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: tier.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tier.icon, size: 16, color: tier.color),
                  const SizedBox(width: 6),
                  Text(tier.name,
                      style: TextStyle(
                          color: tier.color, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LevelsScreen(user: widget.user)));
                    },
                    child: const Text('View progress'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Nice!'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One radial sparkle, flung outward as the animation plays.
  Widget _sparkle(int i, double t, Color color) {
    final angle = (i / 8) * 2 * math.pi;
    final dist = 64.0 * t;
    final dx = math.cos(angle) * dist;
    final dy = math.sin(angle) * dist;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Icon(i.isEven ? Icons.star : Icons.auto_awesome,
            size: i.isEven ? 16 : 12, color: color),
      ),
    );
  }
}
