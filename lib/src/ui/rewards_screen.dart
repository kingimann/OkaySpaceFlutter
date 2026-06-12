import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'profile_decor.dart';

/// Cosmetic rewards gated by level: avatar frames and profile backgrounds that
/// unlock as the user climbs. Unlocked items can be equipped here; locked ones
/// show the level they open at. Backed by the existing on-device [profileDecor].
class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frames = [...kAvatarFrames]
      ..sort((a, b) => frameUnlockLevel(a.id).compareTo(frameUnlockLevel(b.id)));
    final backgrounds = [...kProfileBackgrounds]
      ..sort((a, b) =>
          backgroundUnlockLevel(a.id).compareTo(backgroundUnlockLevel(b.id)));
    final unlockedFrames =
        frames.where((f) => frameUnlockLevel(f.id) <= user.level).length;
    final unlockedBgs = backgrounds
        .where((b) => backgroundUnlockLevel(b.id) <= user.level)
        .length;
    final total = frames.length + backgrounds.length;
    final unlocked = unlockedFrames + unlockedBgs;

    return Scaffold(
      appBar: const OkayAppBar(title: Text('Rewards')),
      body: AnimatedBuilder(
        animation: profileDecor,
        builder: (context, _) => ListView(
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
                  const Icon(Icons.card_giftcard, color: Colors.white, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$unlocked of $total unlocked',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 20)),
                        Text('Level ${user.level} · keep earning to unlock more',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Avatar frames',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.82),
              itemCount: frames.length,
              itemBuilder: (_, i) => _frameTile(context, frames[i]),
            ),
            const SizedBox(height: 24),
            const Text('Profile backgrounds',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.5),
              itemCount: backgrounds.length,
              itemBuilder: (_, i) => _bgTile(context, backgrounds[i]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frameTile(BuildContext context, AvatarFrame f) {
    final scheme = Theme.of(context).colorScheme;
    final reqLevel = frameUnlockLevel(f.id);
    final locked = reqLevel > user.level;
    final equipped = profileDecor.frameId == f.id;

    return GestureDetector(
      onTap: locked
          ? null
          : () {
              profileDecor.save(frame: f.id);
              showInfo(context, equipped ? 'Already equipped' : '${f.name} equipped');
            },
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: equipped
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: equipped ? Border.all(color: scheme.primary) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  framedAvatar(
                    frame: f,
                    surface: scheme.surface,
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.surfaceContainerHighest,
                      child: f.isNone
                          ? Icon(Icons.block, size: 16, color: scheme.outline)
                          : null,
                    ),
                  ),
                  if (locked)
                    const Icon(Icons.lock, size: 18, color: Colors.white70),
                ],
              ),
              const SizedBox(height: 8),
              Text(f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              _statusLabel(context, locked, equipped, reqLevel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bgTile(BuildContext context, ProfileBackground b) {
    final reqLevel = backgroundUnlockLevel(b.id);
    final locked = reqLevel > user.level;
    final equipped = profileDecor.useBackground && profileDecor.backgroundId == b.id;

    return GestureDetector(
      onTap: locked
          ? null
          : () {
              profileDecor.save(background: b.id, useBg: true);
              showInfo(context, '${b.name} background equipped');
            },
      child: Container(
        decoration: BoxDecoration(
          gradient: b.gradient,
          borderRadius: BorderRadius.circular(16),
          border: equipped ? Border.all(color: Colors.white, width: 2.5) : null,
        ),
        child: Stack(
          children: [
            if (locked)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (equipped)
                        const Icon(Icons.check_circle,
                            color: Colors.white, size: 18)
                      else if (locked)
                        const Icon(Icons.lock, color: Colors.white, size: 18),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      Text(
                          locked
                              ? 'Unlocks at level $reqLevel'
                              : equipped
                                  ? 'Equipped'
                                  : 'Tap to equip',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLabel(
      BuildContext context, bool locked, bool equipped, int reqLevel) {
    final scheme = Theme.of(context).colorScheme;
    if (equipped) {
      return Text('Equipped',
          style: TextStyle(
              fontSize: 11, color: scheme.primary, fontWeight: FontWeight.bold));
    }
    if (locked) {
      return Text('Level $reqLevel',
          style: TextStyle(fontSize: 11, color: scheme.outline));
    }
    return Text('Tap to equip',
        style: TextStyle(fontSize: 11, color: scheme.outline));
  }
}
