import 'package:flutter/material.dart';

/// Non-web fallback: the Three.js games need a browser to render.
bool get threeGamesSupported => false;

class ThreeGameView extends StatelessWidget {
  const ThreeGameView({
    super.key,
    required this.gameType,
    this.initialState,
    this.onAction,
    this.onScore,
  });

  final String gameType;
  final Map<String, dynamic>? initialState;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> action)?
      onAction;
  final void Function(int score)? onScore;

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 200,
        child: Center(child: Text('Open on the web to play the 3D version')),
      );
}
