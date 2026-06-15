import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'compose_screen.dart';
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
  // Browsers only allow muted autoplay, so start muted on web.
  bool _muted = kIsWeb;

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

  Future<void> _createReel() async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ComposeScreen()));
    if (created == true && mounted) _reload();
  }

  Future<void> _like(int i) async {
    try {
      final updated = await api.feed.toggleLike(_reels[i].id);
      if (mounted) setState(() => _reels[i] = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _repost(int i) async {
    try {
      final updated = await api.feed.toggleRepost(_reels[i].id);
      if (mounted) setState(() => _reels[i] = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _bookmark(int i) async {
    try {
      final updated = await api.feed.toggleBookmark(_reels[i].id);
      if (mounted) setState(() => _reels[i] = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _more(int i) {
    final post = _reels[i];
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.forward_to_inbox_outlined),
              title: const Text('Share to a chat'),
              onTap: () async {
                Navigator.pop(context);
                final target = await pickConversation(context);
                if (target == null || !mounted) return;
                try {
                  await api.messaging.send(
                      target.id, MessageCreate(type: 'post', postId: post.id));
                  if (mounted) showInfo(context, 'Shared to chat');
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(
                    text: 'https://okayspace.ca/post/${post.id}'));
                if (mounted) showInfo(context, 'Link copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Not interested'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await api.feed.notInterested(post.id);
                  if (mounted) showInfo(context, "We'll show fewer like this.");
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await api.feed.report(post.id, 'inappropriate');
                  if (mounted) showInfo(context, 'Reported. Thank you.');
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: !widget.embedded,
      bottomNavigationBar: null, // pushed screens use the global nav
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
                  // Never a black screen: a branded placeholder reel.
                  return _PlaceholderReel(
                    following: _tab == 1,
                    onRefresh: _reload,
                    onCreate: _createReel,
                  );
                }
                return RefreshIndicator(
                  onRefresh: _reload,
                  child: PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: _reels.length,
                    itemBuilder: (context, i) => _ReelPage(
                      post: _reels[i],
                      muted: _muted,
                      onToggleMute: () => setState(() => _muted = !_muted),
                      onLike: () => _like(i),
                      onRepost: () => _repost(i),
                      onBookmark: () => _bookmark(i),
                      onMore: () => _more(i),
                    ),
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

class _ReelPage extends StatefulWidget {
  const _ReelPage({
    required this.post,
    required this.muted,
    required this.onToggleMute,
    required this.onLike,
    required this.onRepost,
    required this.onBookmark,
    required this.onMore,
  });

  final Post post;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onBookmark;
  final VoidCallback onMore;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  bool _showHeart = false;
  double _speed = 1.0;

  void _doubleTapLike() {
    widget.onLike();
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final media = post.media.isNotEmpty ? post.media.first : null;
    final url = media?.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Media: autoplaying looped video, or a cover image. Double-tap = like.
        GestureDetector(
          onDoubleTap: _doubleTapLike,
          onLongPress: (media?.isVideo ?? false)
              ? () => setState(() => _speed = _speed == 1.0 ? 2.0 : 1.0)
              : null,
          child: (url != null && url.isNotEmpty)
              ? ((media?.isVideo ?? false)
                  ? PostVideo(
                      url: url,
                      poster: media?.thumbnail,
                      autoPlay: true,
                      looping: true,
                      muted: widget.muted,
                      speed: _speed,
                      resolveOnError: () => api.feed.resolveVideoUrl(url),
                    )
                  : Image.network(url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Colors.black)))
              : const ColoredBox(color: Color(0xFF101820)),
        ),
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
        // Mute / unmute toggle.
        if (media?.isVideo ?? false)
          Positioned(
            top: 50,
            right: 12,
            child: GestureDetector(
              onTap: widget.onToggleMute,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        // Speed badge (long-press the video to toggle 1x/2x).
        if ((media?.isVideo ?? false) && _speed != 1.0)
          Positioned(
            top: 50,
            right: 56,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_speed.toStringAsFixed(_speed % 1 == 0 ? 0 : 1)}x',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
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
        // Double-tap "like" heart pop.
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _showHeart ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: _showHeart ? 1 : 0.5,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: const Center(
                child: Icon(Icons.favorite,
                    color: Colors.white,
                    size: 120,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 16)]),
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
                onTap: widget.onLike,
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
                color: post.repostedByMe
                    ? const Color(0xFF22C55E)
                    : Colors.white,
                label: formatCount(post.repostsCount),
                onTap: widget.onRepost,
              ),
              const SizedBox(height: 18),
              _ReelAction(
                icon: post.bookmarkedByMe
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: post.bookmarkedByMe
                    ? const Color(0xFFF6C455)
                    : Colors.white,
                label: formatCount(post.bookmarksCount),
                onTap: widget.onBookmark,
              ),
              const SizedBox(height: 18),
              _ReelAction(
                icon: Icons.more_horiz,
                color: Colors.white,
                label: '',
                onTap: widget.onMore,
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

/// A branded placeholder reel shown when the feed is empty — a photo with a
/// slow Ken Burns zoom, an "OkaySpace Reels" overlay, a 5-second story-style
/// progress bar, and a create/refresh CTA. Never a black screen.
class _PlaceholderReel extends StatefulWidget {
  const _PlaceholderReel({
    required this.following,
    required this.onRefresh,
    required this.onCreate,
  });

  final bool following;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;

  @override
  State<_PlaceholderReel> createState() => _PlaceholderReelState();
}

class _PlaceholderReelState extends State<_PlaceholderReel>
    with SingleTickerProviderStateMixin {
  // 5-second loop drives both the progress bar and the Ken Burns zoom.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  // A stable, brand-seeded stock photo; falls back to a gradient on error.
  static const _photo =
      'https://picsum.photos/seed/okayspacereels/800/1400';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        // ListView so pull-to-refresh works over the full-bleed placeholder.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Ken Burns photo.
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Transform.scale(
                    scale: 1.05 + 0.12 * _c.value,
                    child: child,
                  ),
                  child: Image.network(
                    _photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            OkayColors.primary,
                            Color(0xFF0B141A),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Darkening scrim for legibility.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.black26, Colors.black87],
                    ),
                  ),
                ),
                // Story-style 5-second progress bar.
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 12,
                  right: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _c.value,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                ),
                // Branding + CTA.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: OkayColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow,
                            color: Colors.white, size: 44),
                      ),
                      const SizedBox(height: 16),
                      const Text('OkaySpace',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold)),
                      Text('REELS',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 6)),
                      const SizedBox(height: 14),
                      Text(
                          widget.following
                              ? 'No reels from people you follow yet.'
                              : 'Be the first to post a reel.',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 14)),
                    ],
                  ),
                ),
                // Bottom actions.
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).padding.bottom + 96,
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: OkayColors.primary,
                              foregroundColor: Colors.white),
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.video_call),
                          label: const Text('Create a reel'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => widget.onRefresh(),
                        icon: const Icon(Icons.refresh, color: Colors.white70),
                        label: const Text('Refresh',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
