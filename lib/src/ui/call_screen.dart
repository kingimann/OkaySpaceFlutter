import 'package:flutter/material.dart';

import 'common.dart';

/// A voice or video call screen for a conversation.
///
/// Rings the other participant and fetches a LiveKit media token from the
/// backend. The token + room URL are obtained here; the realtime audio/video
/// transport is provided by the LiveKit SDK once enabled.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.avatarUrl,
    this.video = false,
  });

  final String conversationId;
  final String title;
  final String? avatarUrl;
  final bool video;

  static Future<void> open(
    BuildContext context, {
    required String conversationId,
    required String title,
    String? avatarUrl,
    bool video = false,
  }) =>
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          conversationId: conversationId,
          title: title,
          avatarUrl: avatarUrl,
          video: video,
        ),
      ));

  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _CallState { ringing, connecting, connected, failed }

class _CallScreenState extends State<CallScreen> {
  _CallState _state = _CallState.ringing;
  bool _muted = false;
  late bool _cameraOn = widget.video;
  bool _speaker = true;
  String? _error;
  DateTime? _connectedAt;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await api.messaging.ringCall(widget.conversationId);
      if (!mounted) return;
      setState(() => _state = _CallState.connecting);
      final token = await api.messaging.callToken(widget.conversationId);
      if (!mounted) return;
      // A real media layer would join the LiveKit room using
      // token['token'] and token['url'] here. We mark the call connected
      // once the session token is issued.
      if ((token['token'] ?? token['access_token']) != null) {
        setState(() {
          _state = _CallState.connected;
          _connectedAt = DateTime.now();
        });
      } else {
        setState(() {
          _state = _CallState.failed;
          _error = 'Could not get a call token.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _CallState.failed;
          _error = messageFor(e);
        });
      }
    }
  }

  String get _statusLabel => switch (_state) {
        _CallState.ringing => 'Ringing…',
        _CallState.connecting => 'Connecting…',
        _CallState.connected => 'Connected',
        _CallState.failed => _error ?? 'Call failed',
      };

  /// Records how the call ended in the conversation: a duration if it was
  /// answered, otherwise a missed call.
  void _reportEnd() {
    if (_reported) return;
    _reported = true;
    final connected = _connectedAt != null;
    final ms = connected
        ? DateTime.now().difference(_connectedAt!).inMilliseconds
        : 0;
    api.messaging
        .endCall(widget.conversationId,
            status: connected ? 'ended' : 'missed',
            durationMs: ms,
            video: widget.video)
        .ignore();
  }

  void _end() {
    _reportEnd();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _reportEnd(); // also record if the screen is closed another way
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Avatar(
                url: widget.avatarUrl,
                name: widget.title,
                radius: 56),
            const SizedBox(height: 20),
            Text(widget.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_state == _CallState.ringing ||
                    _state == _CallState.connecting)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54)),
                  ),
                Text(_statusLabel,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 6),
            Text(widget.video ? 'Video call' : 'Voice call',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const Spacer(),
            // In-call controls.
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _control(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: 'Mute',
                    active: _muted,
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  const SizedBox(width: 20),
                  _control(
                    icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                    label: 'Camera',
                    active: _cameraOn,
                    onTap: () => setState(() => _cameraOn = !_cameraOn),
                  ),
                  const SizedBox(width: 20),
                  _control(
                    icon: _speaker ? Icons.volume_up : Icons.hearing,
                    label: 'Speaker',
                    active: _speaker,
                    onTap: () => setState(() => _speaker = !_speaker),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: FloatingActionButton.large(
                heroTag: 'endCall',
                backgroundColor: const Color(0xFFEF4444),
                onPressed: _end,
                child: const Icon(Icons.call_end,
                    color: Colors.white, size: 34),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _control({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? Colors.white : Colors.white24,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon,
                  color: active ? const Color(0xFF0B141A) : Colors.white,
                  size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
