import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'three_game_html.dart';

/// Web build supports the in-app WebGL games.
bool get threeGamesSupported => true;

int _seq = 0;

/// Renders a Three.js game inside a sandboxed iframe (a platform view) and
/// bridges it to Flutter:
///   * arcade games report a final score via [onScore];
///   * backend-driven games send a move via [onAction]; Flutter resolves it
///     against the API and the returned state is pushed back into the iframe.
/// [initialState] seeds backend-driven games (board, players, "you", …).
class ThreeGameView extends StatefulWidget {
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
  State<ThreeGameView> createState() => _ThreeGameViewState();
}

class _ThreeGameViewState extends State<ThreeGameView> {
  late final String _viewType;
  late final String _nonce;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _listener;

  @override
  void initState() {
    super.initState();
    _nonce = 'tg${_seq++}';
    _viewType = 'three-game-$_nonce';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.setAttribute('srcdoc', threeGameHtml(_nonce));
      iframe.setAttribute('sandbox', 'allow-scripts');
      iframe.setAttribute('scrolling', 'no');
      iframe.style.setProperty('border', 'none');
      iframe.style.setProperty('width', '100%');
      iframe.style.setProperty('height', '100%');
      _iframe = iframe;
      return iframe;
    });
    _listener = ((web.Event e) => _onMessage(e)).toJS;
    web.window.addEventListener('message', _listener);
  }

  void _sendToFrame(Map<String, dynamic> payload) {
    final win = _iframe?.contentWindow;
    if (win == null) return;
    (win as JSObject)
        .callMethod('postMessage'.toJS, payload.jsify(), '*'.toJS);
  }

  Future<void> _onMessage(web.Event e) async {
    final data = (e as web.MessageEvent).data.dartify();
    if (data is! Map || data['nonce'] != _nonce) return;
    switch (data['type']) {
      case 'ready':
        _sendToFrame({
          'type': 'init',
          'gameType': widget.gameType,
          'state': widget.initialState ?? const {},
        });
        break;
      case 'score':
        final s = data['score'];
        widget.onScore?.call(s is num ? s.toInt() : 0);
        break;
      case 'action':
        final handler = widget.onAction;
        final action = data['action'];
        if (handler != null && action is Map) {
          final next = await handler(Map<String, dynamic>.from(action));
          if (next != null && mounted) {
            _sendToFrame({'type': 'state', 'state': next});
          }
        }
        break;
    }
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) web.window.removeEventListener('message', l);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
