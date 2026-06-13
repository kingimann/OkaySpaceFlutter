import 'dart:math';

/// Random profile-picture generator backed by DiceBear's HTTP avatar API
/// (https://dicebear.com) — no key, CDN-served PNGs, generated from a style
/// + seed. The app stores the resulting URL as the user's `picture`.

/// Avatar styles offered in the picker (DiceBear collection ids).
const kAvatarStyles = <({String id, String label})>[
  (id: 'avataaars', label: 'Cartoon'),
  (id: 'bottts', label: 'Robots'),
  (id: 'fun-emoji', label: 'Emoji'),
  (id: 'adventurer', label: 'Adventurer'),
  (id: 'big-smile', label: 'Big smile'),
  (id: 'pixel-art', label: 'Pixel'),
  (id: 'thumbs', label: 'Thumbs'),
  (id: 'shapes', label: 'Shapes'),
  (id: 'identicon', label: 'Identicon'),
  (id: 'lorelei', label: 'Lorelei'),
  (id: 'notionists', label: 'Notion'),
  (id: 'micah', label: 'Micah'),
];

final _rng = Random();

/// A random seed string for a fresh avatar.
String randomAvatarSeed() =>
    'okay${_rng.nextInt(1 << 32).toRadixString(36)}${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

/// A DiceBear PNG avatar URL for [style] + [seed] (defaults: random).
String avatarUrl({String? style, String? seed, int size = 256}) {
  final s = style ?? kAvatarStyles[_rng.nextInt(kAvatarStyles.length)].id;
  final sd = seed ?? randomAvatarSeed();
  return 'https://api.dicebear.com/9.x/$s/png'
      '?seed=${Uri.encodeQueryComponent(sd)}&size=$size';
}
