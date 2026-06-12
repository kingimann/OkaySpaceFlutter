import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local profile decoration, mirroring okayspace.ca's `profileCustomize.ts`:
/// 8 colour themes, 16 avatar frames and 13 profile backgrounds. Selections
/// are stored on-device (the REST API has no decoration endpoints yet).

class ProfileTheme {
  const ProfileTheme(this.id, this.name, this.accent);
  final String id;
  final String name;
  final Color accent;
}

class AvatarFrame {
  const AvatarFrame(this.id, this.name, this.colors, {this.width = 3});
  final String id;
  final String name;

  /// One colour = solid ring; two+ = sweep gradient ring. Empty = no frame.
  final List<Color> colors;
  final double width;

  bool get isNone => colors.isEmpty;
}

class ProfileBackground {
  const ProfileBackground(this.id, this.name, this.colors);
  final String id;
  final String name;
  final List<Color> colors;

  Gradient get gradient => LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors);
}

const kProfileThemes = <ProfileTheme>[
  ProfileTheme('default', 'Default', Color(0xFF14B8A6)),
  ProfileTheme('ocean', 'Ocean', Color(0xFF2563EB)),
  ProfileTheme('sunset', 'Sunset', Color(0xFFF97316)),
  ProfileTheme('forest', 'Forest', Color(0xFF16A34A)),
  ProfileTheme('berry', 'Berry', Color(0xFFDB2777)),
  ProfileTheme('midnight', 'Midnight', Color(0xFF6366F1)),
  ProfileTheme('gold', 'Gold', Color(0xFFEAB308)),
  ProfileTheme('rose', 'Rose', Color(0xFFE11D48)),
];

const kAvatarFrames = <AvatarFrame>[
  AvatarFrame('none', 'None', []),
  AvatarFrame('teal', 'Teal', [Color(0xFF14B8A6)]),
  AvatarFrame('blue', 'Blue', [Color(0xFF2563EB)]),
  AvatarFrame('gold', 'Gold', [Color(0xFFEAB308)]),
  AvatarFrame('rose', 'Rose', [Color(0xFFE11D48)]),
  AvatarFrame('violet', 'Violet', [Color(0xFF8B5CF6)]),
  AvatarFrame('sunset', 'Sunset', [Color(0xFFF97316), Color(0xFFE11D48)]),
  AvatarFrame('ocean', 'Ocean', [Color(0xFF06B6D4), Color(0xFF2563EB)]),
  AvatarFrame('forest', 'Forest', [Color(0xFF22C55E), Color(0xFF065F46)]),
  AvatarFrame('candy', 'Candy', [Color(0xFFEC4899), Color(0xFF8B5CF6)]),
  AvatarFrame('fire', 'Fire', [Color(0xFFFACC15), Color(0xFFEF4444)]),
  AvatarFrame('aurora', 'Aurora',
      [Color(0xFF22D3EE), Color(0xFF818CF8), Color(0xFFF472B6)]),
  AvatarFrame('rainbow', 'Rainbow', [
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ]),
  AvatarFrame('mono', 'Mono', [Color(0xFF111827), Color(0xFF6B7280)]),
  AvatarFrame('emerald', 'Emerald', [Color(0xFF10B981), Color(0xFF34D399)],
      width: 4),
  AvatarFrame('royal', 'Royal', [Color(0xFF4338CA), Color(0xFFA78BFA)],
      width: 4),
];

const kProfileBackgrounds = <ProfileBackground>[
  ProfileBackground('teal', 'Teal', [Color(0xFF14B8A6), Color(0xFF0F766E)]),
  ProfileBackground('ocean', 'Ocean', [Color(0xFF3B82F6), Color(0xFF1E3A8A)]),
  ProfileBackground('sunset', 'Sunset', [Color(0xFFF97316), Color(0xFFBE123C)]),
  ProfileBackground('forest', 'Forest', [Color(0xFF22C55E), Color(0xFF14532D)]),
  ProfileBackground('berry', 'Berry', [Color(0xFFDB2777), Color(0xFF701A75)]),
  ProfileBackground(
      'midnight', 'Midnight', [Color(0xFF1E293B), Color(0xFF0F172A)]),
  ProfileBackground('gold', 'Gold', [Color(0xFFF59E0B), Color(0xFF92400E)]),
  ProfileBackground('rose', 'Rose', [Color(0xFFFB7185), Color(0xFF9F1239)]),
  ProfileBackground('aurora', 'Aurora', [Color(0xFF22D3EE), Color(0xFF8B5CF6)]),
  ProfileBackground('peach', 'Peach', [Color(0xFFFDBA74), Color(0xFFF472B6)]),
  ProfileBackground('mint', 'Mint', [Color(0xFF5EEAD4), Color(0xFF2563EB)]),
  ProfileBackground('grape', 'Grape', [Color(0xFFA78BFA), Color(0xFF6D28D9)]),
  ProfileBackground('slate', 'Slate', [Color(0xFF64748B), Color(0xFF334155)]),
];

/// The level at which each avatar frame unlocks (anything unlisted is
/// available from the start). Fancier frames sit higher up the ladder, giving
/// points/levels a tangible cosmetic payoff.
const kFrameUnlocks = <String, int>{
  'candy': 4,
  'fire': 6,
  'ocean': 6,
  'forest': 8,
  'emerald': 12,
  'aurora': 15,
  'rainbow': 20,
  'royal': 28,
};

/// The level at which an avatar frame unlocks (1 = always available).
int frameUnlockLevel(String id) => kFrameUnlocks[id] ?? 1;

/// The level at which each profile background unlocks.
const kBackgroundUnlocks = <String, int>{
  'midnight': 4,
  'peach': 8,
  'mint': 10,
  'aurora': 15,
  'grape': 20,
  'slate': 25,
};

/// The level at which a profile background unlocks (1 = always available).
int backgroundUnlockLevel(String id) => kBackgroundUnlocks[id] ?? 1;

/// Persists the user's chosen theme/frame/background ids on-device.
class ProfileDecorController extends ChangeNotifier {
  ProfileDecorController() {
    _load();
  }

  static const _key = 'okayspace.profile_decor';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String themeId = 'default';
  String frameId = 'none';
  String backgroundId = 'teal';
  bool useBackground = false; // when true, the gradient overrides cover/accent

  ProfileTheme get theme => kProfileThemes
      .firstWhere((t) => t.id == themeId, orElse: () => kProfileThemes.first);
  AvatarFrame get frame => kAvatarFrames
      .firstWhere((f) => f.id == frameId, orElse: () => kAvatarFrames.first);
  ProfileBackground get background => kProfileBackgrounds.firstWhere(
      (b) => b.id == backgroundId,
      orElse: () => kProfileBackgrounds.first);

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final parts = raw.split('|');
      if (parts.length >= 4) {
        themeId = parts[0];
        frameId = parts[1];
        backgroundId = parts[2];
        useBackground = parts[3] == '1';
        notifyListeners();
      }
    } catch (_) {/* keep defaults */}
  }

  Future<void> save({
    String? theme,
    String? frame,
    String? background,
    bool? useBg,
  }) async {
    if (theme != null) themeId = theme;
    if (frame != null) frameId = frame;
    if (background != null) backgroundId = background;
    if (useBg != null) useBackground = useBg;
    notifyListeners();
    try {
      await _storage.write(
          key: _key,
          value: '$themeId|$frameId|$backgroundId|${useBackground ? 1 : 0}');
    } catch (_) {/* best effort */}
  }
}

final ProfileDecorController profileDecor = ProfileDecorController();

/// Wraps [child] (an avatar) in the given decorative ring.
Widget framedAvatar({
  required Widget child,
  required AvatarFrame frame,
  required Color surface,
  double pad = 3,
}) {
  if (frame.isNone) {
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
      child: child,
    );
  }
  final gradient = SweepGradient(
    colors: frame.colors.length == 1
        ? [frame.colors.first, frame.colors.first]
        : [...frame.colors, frame.colors.first],
  );
  return Container(
    padding: EdgeInsets.all(frame.width),
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
    child: Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
      child: child,
    ),
  );
}

/// A bottom sheet for picking theme / avatar frame / background.
void showProfileDecorSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AnimatedBuilder(
      animation: profileDecor,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (_, ctrl) => ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Customize profile',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in kProfileThemes)
                      GestureDetector(
                        onTap: () => profileDecor.save(theme: t.id),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: t.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: profileDecor.themeId == t.id
                                        ? scheme.onSurface
                                        : Colors.transparent,
                                    width: 3),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(t.name, style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Avatar frame',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final f in kAvatarFrames)
                      GestureDetector(
                        onTap: () => profileDecor.save(frame: f.id),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: profileDecor.frameId == f.id
                                    ? scheme.primary
                                    : Colors.transparent,
                                width: 2),
                          ),
                          child: framedAvatar(
                            frame: f,
                            surface: scheme.surface,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: scheme.surfaceContainerHighest,
                              child: f.isNone
                                  ? Icon(Icons.block,
                                      size: 14, color: scheme.outline)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Profile background',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Switch(
                      value: profileDecor.useBackground,
                      onChanged: (v) => profileDecor.save(useBg: v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final b in kProfileBackgrounds)
                      GestureDetector(
                        onTap: () =>
                            profileDecor.save(background: b.id, useBg: true),
                        child: Container(
                          width: 64,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: b.gradient,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: profileDecor.backgroundId == b.id
                                    ? scheme.onSurface
                                    : Colors.transparent,
                                width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
