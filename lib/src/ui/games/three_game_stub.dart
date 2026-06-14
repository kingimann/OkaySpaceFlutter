import 'package:flutter/material.dart';

/// Non-web fallback: the Three.js games need a browser to render.
bool get threeGamesSupported => false;

class ThreeGameView extends StatelessWidget {
  const ThreeGameView(
      {super.key, required this.gameType, required this.onScore});

  final String gameType;
  final void Function(int score) onScore;

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 200,
        child: Center(child: Text('Open on the web to play the 3D version')),
      );
}
