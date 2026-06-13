import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Random profile-picture generator. Two modes:
///  • LOCAL identicons rendered in-app (no network — always works).
///  • DiceBear HTTP avatars (cartoon/robots/etc) when the network allows.
/// The local generator is the default so "Generate" never fails.

final _rng = Random();

/// A random seed integer.
int randomSeed() => _rng.nextInt(1 << 31);

// --- Local identicon avatars (offline, reliable) ---------------------------

/// Renders a colorful symmetric identicon to PNG bytes — entirely on-device,
/// so it works with no network. Deterministic for a given [seed].
Future<Uint8List> renderIdenticon(int seed, {int size = 256}) async {
  final rnd = Random(seed);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size.toDouble();

  // Two-tone diagonal background.
  final hue = rnd.nextDouble() * 360;
  final bgA = HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
  final bgB = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.42).toColor();
  canvas.drawRect(
    Rect.fromLTWH(0, 0, s, s),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bgA, bgB],
      ).createShader(Rect.fromLTWH(0, 0, s, s)),
  );

  // 5×5 mirrored blocky pattern in white.
  const cells = 5;
  final cell = s / cells;
  final fg = Paint()..color = Colors.white.withValues(alpha: 0.92);
  for (var x = 0; x < (cells / 2).ceil(); x++) {
    for (var y = 0; y < cells; y++) {
      if (rnd.nextBool()) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x * cell, y * cell, cell, cell),
                const Radius.circular(3)),
            fg);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH((cells - 1 - x) * cell, y * cell, cell, cell),
                const Radius.circular(3)),
            fg);
      }
    }
  }

  final picture = recorder.endRecording();
  final img = await picture.toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  // Release the native image/picture — every identicon would otherwise leak.
  img.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// A batch of [count] local identicon avatars (PNG bytes).
Future<List<Uint8List>> identiconBatch({int count = 12, int size = 256}) async {
  return Future.wait(
      [for (var i = 0; i < count; i++) renderIdenticon(randomSeed(), size: size)]);
}

// --- DiceBear (optional, networked) ----------------------------------------

const kAvatarStyles = <({String id, String label})>[
  (id: 'avataaars', label: 'Cartoon'),
  (id: 'bottts', label: 'Robots'),
  (id: 'fun-emoji', label: 'Emoji'),
  (id: 'adventurer', label: 'Adventurer'),
  (id: 'big-smile', label: 'Big smile'),
  (id: 'pixel-art', label: 'Pixel'),
  (id: 'thumbs', label: 'Thumbs'),
  (id: 'shapes', label: 'Shapes'),
  (id: 'lorelei', label: 'Lorelei'),
  (id: 'micah', label: 'Micah'),
];

String randomAvatarSeed() =>
    'okay${_rng.nextInt(1 << 32).toRadixString(36)}${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

/// A DiceBear PNG avatar URL for [style] + [seed].
String avatarUrl({String? style, String? seed, int size = 256}) {
  final st = style ?? kAvatarStyles[_rng.nextInt(kAvatarStyles.length)].id;
  final sd = seed ?? randomAvatarSeed();
  return 'https://api.dicebear.com/9.x/$st/png'
      '?seed=${Uri.encodeQueryComponent(sd)}&size=$size';
}

/// A batch of DiceBear URLs (random style when [style] is null).
List<String> avatarBatch({String? style, int count = 12}) =>
    [for (var i = 0; i < count; i++) avatarUrl(style: style)];
