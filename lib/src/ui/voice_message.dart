import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'util/recording_bytes.dart';

/// Records a voice note and sends it to [convId]. Opens a bottom sheet that
/// starts recording immediately; the user can send or cancel.
Future<bool> recordAndSendVoice(BuildContext context, String convId) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _VoiceRecorderSheet(convId: convId),
  );
  return sent ?? false;
}

class _VoiceRecorderSheet extends StatefulWidget {
  const _VoiceRecorderSheet({required this.convId});
  final String convId;

  @override
  State<_VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<_VoiceRecorderSheet> {
  final _rec = AudioRecorder();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = 'Microphone permission denied.');
        return;
      }
      await _rec.start(const RecordConfig(), path: 'voice');
      if (!mounted) return;
      setState(() => _recording = true);
      _ticker = Timer.periodic(const Duration(seconds: 1),
          (_) => setState(() => _elapsed += const Duration(seconds: 1)));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start recording.');
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    try {
      if (await _rec.isRecording()) await _rec.cancel();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _send() async {
    _ticker?.cancel();
    setState(() {
      _recording = false;
      _sending = true;
    });
    try {
      final path = await _rec.stop();
      if (path == null) throw Exception('No recording');
      final bytes = await readRecording(path);
      if (bytes == null || bytes.isEmpty) throw Exception('Empty recording');
      await api.messaging.send(
        widget.convId,
        MessageCreate(
          type: 'voice',
          audioBase64: base64Encode(bytes),
          audioDurationMs: _elapsed.inMilliseconds,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Could not send the voice message.';
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rec.dispose();
    super.dispose();
  }

  String get _time {
    final m = _elapsed.inMinutes;
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close')),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic,
                      color: _recording ? scheme.error : scheme.outline),
                  const SizedBox(width: 10),
                  Text(_time,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Text(_sending ? 'Sending…' : 'Recording…',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: _sending ? null : _cancel,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: (_sending || !_recording) ? null : _send,
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plays a voice message from its base64 audio. Shows a play/pause button and
/// the duration; a compact control suitable for a chat bubble.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({super.key, required this.base64Audio, this.durationMs, this.dark = false});
  final String base64Audio;
  final int? durationMs;
  final bool dark;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  Duration _pos = Duration.zero;
  StreamSubscription? _stateSub, _posSub;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) {
        setState(() => _playing = s == PlayerState.playing);
      }
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_pos > Duration.zero) {
        await _player.resume();
        return;
      }
      setState(() => _loading = true);
      final bytes = base64Decode(widget.base64Audio);
      await _player.play(BytesSource(bytes));
    } catch (_) {
      if (mounted) showError(context, 'Could not play this voice message.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final total = widget.durationMs != null && widget.durationMs! > 0
        ? Duration(milliseconds: widget.durationMs!)
        : null;
    final shown = _pos > Duration.zero ? _pos : (total ?? Duration.zero);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _loading ? null : _toggle,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_playing ? Icons.pause_circle : Icons.play_circle,
                  color: fg, size: 32),
        ),
        Icon(Icons.graphic_eq, color: fg.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(_fmt(shown), style: TextStyle(color: fg, fontFeatures: const [])),
      ],
    );
  }
}
