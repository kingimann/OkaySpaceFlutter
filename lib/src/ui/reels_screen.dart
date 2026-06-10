import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_detail_screen.dart';
import 'post_video.dart';
import 'profile_screen.dart';

/// A full-screen, vertically-swiping reels feed.
///
/// Renders each reel's media as a cover image with an overlay (author, caption,
/// engagement). Videos show a play affordance over the thumbnail — actual video
/// playback would need a video plugin; this keeps it dependency-free.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, this.embedded = false});

  /// True as a home tab (shell provides the nav); false when pushed standalone.
  final bool embedded;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late Future<List<Post>> _future;
  List<Post> _reels = const [];
  int _tab = 0; // 0 = Explore (popular), 1 = Following (personalized)

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Post>> _load() async {
    // Explore = popular reels; Following = the personalized reels feed.
    var reels = _tab == 1
        ? await api.feed.reelsFeed()
        : await api.feed.popularReels();
    // Either feed can be empty (e.g. new accounts); fall back to the other so
    // the screen still has something to show.
    if (reels.isEmpty) {
      try {
        reels = _tab == 1
            ? await api.feed.popularReels()
            : await api.feed.reelsFeed();
      } catch (_) {/* keep the empty list */}
    }
    _reels = reels;
    return reels;
  }

  void _setTab(int t) {
    if (t == _tab) return;
    setState(() {
      _tab = t;
      _future = _load();
    });
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _like(int i) async {
    try {
      final updated = await api.feed.toggleLike(_reels[i].id);
      if (mounted) setState(() => _reels[i] = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: !widget.embedded,
      bottomNavigationBar: widget.embedded ? null : const OkayBottomNav(),
      body: Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder<List<Post>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _DarkMessage(
                      message: messageFor(snapshot.error), onRetry: _reload);
                }
                if (_reels.isEmpty) {
                  return _DarkMessage(
                      message: _tab == 1
                          ? 'No reels from people you follow yet.'
                          : 'No reels yet.',
                      onRetry: _reload);
                }
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: _reels.length,
                    itemBuilder: (context, i) =>
                        _ReelPage(post: _reels[i], onLike: () => _like(i)),
                  ),
                );
              },
            ),
          ),
          // Top overlay: the sidebar menu (like every other screen) and the
          // Explore / Following tabs, Instagram-style.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 48,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        tooltip: 'Menu',
                        onPressed: () => openSidebar(context),
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _topTab('Explore', 0),
                          const SizedBox(width: 24),
                          _topTab('Following', 1),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topTab(String label, int idx) {
    final selected = _tab == idx;
    return GestureDetector(
      onTap: () => _setTab(idx),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              fontSize: 16,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 3,
            width: selected ? 20 : 0,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelPage extends StatelessWidget {
  const _ReelPage({required this.post, required this.onLike});

  final Post post;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final media = post.media.isNotEmpty ? post.media.first : null;
    final url = media?.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Media: autoplaying looped video, or a cover image.
        if (url != null && url.isNotEmpty)
          (media?.isVideo ?? false)
              ? PostVideo(
                  url: url,
                  poster: media?.thumbnail,
                  autoPlay: true,
                  looping: true,
                  // Browsers only allow muted autoplay; start muted on web so
                  // reels actually play (tap toggles play/pause).
                  muted: kIsWeb,
                  resolveOnError: () => api.feed.resolveVideoUrl(url),
                )
              : Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black))
        else
          const ColoredBox(color: Color(0xFF101820)),
        // Bottom gradient for legibility.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
        // Top scrim for status-bar legibility.
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 90,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
        ),
        // Caption + author (bottom-left).
        Positioned(
          left: 16,
          right: 80,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => ProfileScreen.open(context, post.author.userId),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Avatar(
                        url: post.author.picture,
                        name: post.author.name,
                        radius: 18),
                    const SizedBox(width: 8),
                    Text(
                      post.author.username != null
                          ? '@${post.author.username}'
                          : post.author.name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(post.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
        ),
        // Action rail (bottom-right).
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReelAction(
                icon: post.likedByMe ? Icons.favorite : Icons.favorite_border,
                color: post.likedByMe ? Colors.red : Colors.white,
                label: formatCount(post.likesCount),
                onTap: onLike,
              ),
              const SizedBox(height: 18),
              _ReelAction(
                icon: Icons.mode_comment_outlined,
                color: Colors.white,
                label: formatCount(post.repliesCount),
                onTap: () => PostDetailScreen.open(context, post),
              ),
              const SizedBox(height: 18),
              _ReelAction(
                icon: Icons.repeat,
                color: Colors.white,
                label: formatCount(post.repostsCount),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReelAction extends StatelessWidget {
  const _ReelAction({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DarkMessage extends StatelessWidget {
  const _DarkMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
