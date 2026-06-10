import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Inline network-video player with a center play/pause affordance.
///
/// - In the feed, use [autoPlay] = false: shows the first frame with a play
///   button; tap to play/pause.
/// - In reels, use [autoPlay] = true and [looping] = true for an autoplaying
///   loop; tap toggles play/pause.
class PostVideo extends StatefulWidget {
  const PostVideo({
    super.key,
    required this.url,
    this.poster,
    this.autoPlay = false,
    this.looping = false,
    this.muted = false,
  });

  final String url;

  /// Optional thumbnail shown while the video loads or if playback fails,
  /// so the surface is never just black.
  final String? poster;
  final bool autoPlay;
  final bool looping;
  final bool muted;

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(widget.looping);
      if (widget.muted) c.setVolume(0);
      if (widget.autoPlay) c.play();
      setState(() => _ready = true);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  /// The poster thumbnail, or a plain black fill if none is available.
  Widget _posterOrBlack() {
    final poster = widget.poster;
    if (poster != null && poster.isNotEmpty) {
      return Image.network(poster,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black));
    }
    return const ColoredBox(color: Colors.black);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _posterOrBlack(),
          const Center(
              child: Icon(Icons.videocam_off_outlined, color: Colors.white54)),
        ],
      );
    }
    if (c == null || !_ready) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _posterOrBlack(),
          const Center(
              child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      );
    }
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.passthrough,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          // Center play button when paused.
          AnimatedOpacity(
            opacity: c.value.isPlaying ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
            ),
          ),
          // Slim progress bar at the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: false,
              colors: const VideoProgressColors(
                playedColor: Color(0xFF00A884),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
