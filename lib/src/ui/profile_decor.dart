import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local profile decoration. Selections are stored on-device (the REST API
/// has no decoration endpoints yet). Categories: colour theme, avatar frame,
/// profile background, avatar shape, name effect and background pattern.

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

/// Avatar outline shape.
class AvatarShape {
  const AvatarShape(this.id, this.name);
  final String id;
  final String name;
}

/// How the display name is painted.
class NameEffect {
  const NameEffect(this.id, this.name);
  final String id;
  final String name;
}

/// A decorative overlay drawn over the profile background.
class ProfilePattern {
  const ProfilePattern(this.id, this.name);
  final String id;
  final String name;
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
  // More accents.
  ProfileTheme('crimson', 'Crimson', Color(0xFFDC2626)),
  ProfileTheme('sky', 'Sky', Color(0xFF0EA5E9)),
  ProfileTheme('lime', 'Lime', Color(0xFF65A30D)),
  ProfileTheme('amber', 'Amber', Color(0xFFF59E0B)),
  ProfileTheme('magenta', 'Magenta', Color(0xFFC026D3)),
  ProfileTheme('indigo', 'Indigo', Color(0xFF4F46E5)),
  ProfileTheme('cyan', 'Cyan', Color(0xFF06B6D4)),
  ProfileTheme('coral', 'Coral', Color(0xFFFB7185)),
  ProfileTheme('emerald', 'Emerald', Color(0xFF10B981)),
  ProfileTheme('plum', 'Plum', Color(0xFF7C3AED)),
  ProfileTheme('bronze', 'Bronze', Color(0xFFB45309)),
  ProfileTheme('slate', 'Slate', Color(0xFF475569)),
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
  // More frames.
  AvatarFrame('crimson', 'Crimson', [Color(0xFFDC2626)]),
  AvatarFrame('sky', 'Sky', [Color(0xFF0EA5E9)]),
  AvatarFrame('lime', 'Lime', [Color(0xFF84CC16)]),
  AvatarFrame('amber', 'Amber', [Color(0xFFF59E0B)]),
  AvatarFrame('magenta', 'Magenta', [Color(0xFFC026D3)]),
  AvatarFrame('mint', 'Mint', [Color(0xFF34D399), Color(0xFF22D3EE)]),
  AvatarFrame('peach', 'Peach', [Color(0xFFFDBA74), Color(0xFFFB7185)]),
  AvatarFrame('grape', 'Grape', [Color(0xFFA78BFA), Color(0xFF6D28D9)]),
  AvatarFrame('toxic', 'Toxic', [Color(0xFFA3E635), Color(0xFF16A34A)]),
  AvatarFrame('ice', 'Ice', [Color(0xFFE0F2FE), Color(0xFF38BDF8)]),
  AvatarFrame('lava', 'Lava', [Color(0xFFF59E0B), Color(0xFFB91C1C)], width: 4),
  AvatarFrame('galaxy', 'Galaxy',
      [Color(0xFF312E81), Color(0xFF7C3AED), Color(0xFFDB2777)], width: 4),
  AvatarFrame('gilded', 'Gilded', [Color(0xFFFDE68A), Color(0xFFB45309)],
      width: 4),
  AvatarFrame('neon', 'Neon',
      [Color(0xFF22D3EE), Color(0xFFEC4899), Color(0xFF22D3EE)], width: 4),
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
  // More backgrounds.
  ProfileBackground('ember', 'Ember', [Color(0xFFEF4444), Color(0xFF7C2D12)]),
  ProfileBackground('lagoon', 'Lagoon', [Color(0xFF2DD4BF), Color(0xFF0E7490)]),
  ProfileBackground('plum', 'Plum', [Color(0xFFD946EF), Color(0xFF581C87)]),
  ProfileBackground('storm', 'Storm', [Color(0xFF334155), Color(0xFF0B1120)]),
  ProfileBackground('lime', 'Lime', [Color(0xFF84CC16), Color(0xFF3F6212)]),
  ProfileBackground('candy', 'Candy', [Color(0xFFF472B6), Color(0xFF818CF8)]),
  ProfileBackground('mocha', 'Mocha', [Color(0xFFB45309), Color(0xFF44403C)]),
  ProfileBackground('sunrise', 'Sunrise',
      [Color(0xFFFDE68A), Color(0xFFFB7185)]),
  ProfileBackground('deepsea', 'Deep sea',
      [Color(0xFF0EA5E9), Color(0xFF0C4A6E)]),
  ProfileBackground('nebula', 'Nebula', [Color(0xFF6D28D9), Color(0xFF1E1B4B)]),
  ProfileBackground('frost', 'Frost', [Color(0xFFE0F2FE), Color(0xFF7DD3FC)]),
  ProfileBackground('noir', 'Noir', [Color(0xFF111827), Color(0xFF000000)]),
];

const kAvatarShapes = <AvatarShape>[
  AvatarShape('circle', 'Circle'),
  AvatarShape('rounded', 'Rounded'),
  AvatarShape('squircle', 'Squircle'),
  AvatarShape('hexagon', 'Hexagon'),
];

const kNameEffects = <NameEffect>[
  NameEffect('plain', 'Plain'),
  NameEffect('accent', 'Accent colour'),
  NameEffect('gradient', 'Gradient'),
];

const kPatterns = <ProfilePattern>[
  ProfilePattern('none', 'None'),
  ProfilePattern('dots', 'Dots'),
  ProfilePattern('grid', 'Grid'),
  ProfilePattern('diagonal', 'Diagonal'),
];

/// The level at which each avatar frame unlocks (anything unlisted is
/// available from the start). Fancier frames sit higher up the ladder.
const kFrameUnlocks = <String, int>{
  'candy': 4,
  'fire': 6,
  'ocean': 6,
  'forest': 8,
  'emerald': 12,
  'aurora': 15,
  'rainbow': 20,
  'royal': 28,
  'lava': 14,
  'galaxy': 22,
  'gilded': 26,
  'neon': 30,
};

int frameUnlockLevel(String id) => kFrameUnlocks[id] ?? 1;

const kBackgroundUnlocks = <String, int>{
  'midnight': 4,
  'peach': 8,
  'mint': 10,
  'aurora': 15,
  'grape': 20,
  'slate': 25,
  'nebula': 18,
  'deepsea': 12,
  'noir': 24,
};

int backgroundUnlockLevel(String id) => kBackgroundUnlocks[id] ?? 1;

/// Persists the user's chosen decoration ids on-device.
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
  String avatarShapeId = 'circle';
  String nameEffectId = 'plain';
  String patternId = 'none';

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
      // Backward-compatible: the old format stored 4 fields.
      if (parts.length >= 4) {
        themeId = parts[0];
        frameId = parts[1];
        backgroundId = parts[2];
        useBackground = parts[3] == '1';
      }
      if (parts.length >= 7) {
        avatarShapeId = parts[4];
        nameEffectId = parts[5];
        patternId = parts[6];
      }
      notifyListeners();
    } catch (_) {/* keep defaults */}
  }

  Future<void> save({
    String? theme,
    String? frame,
    String? background,
    bool? useBg,
    String? avatarShape,
    String? nameEffect,
    String? pattern,
  }) async {
    if (theme != null) themeId = theme;
    if (frame != null) frameId = frame;
    if (background != null) backgroundId = background;
    if (useBg != null) useBackground = useBg;
    if (avatarShape != null) avatarShapeId = avatarShape;
    if (nameEffect != null) nameEffectId = nameEffect;
    if (pattern != null) patternId = pattern;
    notifyListeners();
    try {
      await _storage.write(
          key: _key,
          value: '$themeId|$frameId|$backgroundId|${useBackground ? 1 : 0}'
              '|$avatarShapeId|$nameEffectId|$patternId');
    } catch (_) {/* best effort */}
  }
}

final ProfileDecorController profileDecor = ProfileDecorController();

/// Clips an avatar to the chosen [shapeId].
class _HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height, path = Path();
    final cx = w / 2, cy = h / 2, r = math.min(w, h) / 2;
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 180 * (60 * i - 30);
      final x = cx + r * math.cos(a), y = cy + r * math.sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_HexagonClipper oldClipper) => false;
}

Widget _clipShape(String shapeId, Widget child, double size) {
  switch (shapeId) {
    case 'rounded':
      return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.28), child: child);
    case 'squircle':
      return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.42), child: child);
    case 'hexagon':
      return ClipPath(clipper: _HexagonClipper(), child: child);
    default:
      return ClipOval(child: child);
  }
}

BoxDecoration _shapeDecoration(String shapeId, {Color? color, Gradient? gradient}) {
  switch (shapeId) {
    case 'rounded':
      return BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(16));
    case 'squircle':
      return BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(22));
    default: // circle + hexagon both use a circle-ish base; hexagon clips child
      return BoxDecoration(
          color: color, gradient: gradient, shape: BoxShape.circle);
  }
}

/// Wraps [child] (an avatar) in the given decorative ring and shape.
Widget framedAvatar({
  required Widget child,
  required AvatarFrame frame,
  required Color surface,
  double pad = 3,
  String shape = 'circle',
  double size = 90,
}) {
  // Hexagon needs a hard clip; other shapes use a decoration with the right
  // border radius.
  Widget shaped(Widget c) =>
      shape == 'hexagon' ? _clipShape('hexagon', c, size) : c;

  if (frame.isNone) {
    return shaped(Container(
      padding: EdgeInsets.all(pad),
      decoration: _shapeDecoration(shape, color: surface),
      child: shape == 'hexagon' ? child : _clipShape(shape, child, size),
    ));
  }
  final gradient = SweepGradient(
    colors: frame.colors.length == 1
        ? [frame.colors.first, frame.colors.first]
        : [...frame.colors, frame.colors.first],
  );
  return shaped(Container(
    padding: EdgeInsets.all(frame.width),
    decoration: _shapeDecoration(shape, gradient: gradient),
    child: Container(
      padding: EdgeInsets.all(pad),
      decoration: _shapeDecoration(shape, color: surface),
      child: shape == 'hexagon' ? child : _clipShape(shape, child, size),
    ),
  ));
}

/// The display-name widget styled per the chosen name effect.
Widget profileNameText(String name, TextStyle? base,
    {required Color accent, TextAlign? align}) {
  switch (profileDecor.nameEffectId) {
    case 'accent':
      return Text(name, textAlign: align, style: base?.copyWith(color: accent));
    case 'gradient':
      return ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          colors: [accent, _lighten(accent, 0.35)],
        ).createShader(rect),
        blendMode: BlendMode.srcIn,
        child: Text(name,
            textAlign: align,
            style: base?.copyWith(color: Colors.white)),
      );
    default:
      return Text(name, textAlign: align, style: base);
  }
}

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .toColor();
}

/// Paints the selected pattern overlay over a profile background.
class ProfilePatternPainter extends CustomPainter {
  ProfilePatternPainter(this.patternId, {this.color = Colors.white24});
  final String patternId;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeWidth = 1;
    switch (patternId) {
      case 'dots':
        for (var y = 8.0; y < size.height; y += 18) {
          for (var x = 8.0; x < size.width; x += 18) {
            canvas.drawCircle(Offset(x, y), 1.6, paint);
          }
        }
      case 'grid':
        paint.style = PaintingStyle.stroke;
        for (var x = 0.0; x < size.width; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (var y = 0.0; y < size.height; y += 20) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case 'diagonal':
        paint.style = PaintingStyle.stroke;
        for (var x = -size.height; x < size.width; x += 16) {
          canvas.drawLine(
              Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
    }
  }

  @override
  bool shouldRepaint(ProfilePatternPainter oldDelegate) =>
      oldDelegate.patternId != patternId || oldDelegate.color != color;
}

/// A bottom sheet for picking every profile decoration.
void showProfileDecorSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AnimatedBuilder(
      animation: profileDecor,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        Widget header(String t) => Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
            );
        Widget chip(String label, bool selected, VoidCallback onTap) =>
            ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) => onTap(),
            );
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.95,
            builder: (_, ctrl) => ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Customize profile',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                header('Theme'),
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
                header('Avatar frame'),
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
                            size: 40,
                            shape: profileDecor.avatarShapeId,
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
                header('Avatar shape'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in kAvatarShapes)
                      chip(s.name, profileDecor.avatarShapeId == s.id,
                          () => profileDecor.save(avatarShape: s.id)),
                  ],
                ),
                header('Name effect'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final n in kNameEffects)
                      chip(n.name, profileDecor.nameEffectId == n.id,
                          () => profileDecor.save(nameEffect: n.id)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 8),
                  child: Row(
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
                ),
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
                header('Background pattern'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in kPatterns)
                      chip(p.name, profileDecor.patternId == p.id,
                          () => profileDecor.save(pattern: p.id)),
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
