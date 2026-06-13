import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import '../core/cloudinary_api.dart';
import 'common.dart';
import 'post_detail_screen.dart';
import 'post_video.dart';
import 'profile_screen.dart';

/// The first playable video URL of a post (YouTube-style videos are posts
/// with a title + a video media item), or null.
PostMedia? _videoOf(Post p) {
  for (final m in p.media) {
    if (m.isVideo && (m.url ?? '').isNotEmpty) return m;
  }
  return null;
}

/// A "video" (vs a Reel) is a titled video post — the title is what the
/// uploader gives it in the YouTube-style composer.
bool _isVideoPost(Post p) =>
    (p.title ?? '').trim().isNotEmpty && _videoOf(p) != null;

/// YouTube-style videos home: a scrollable list of landscape video cards,
/// pulled from the reels feed + popular and filtered to titled videos.
class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  late Future<List<Post>> _videos = _load();

  Future<List<Post>> _load() async {
    // The reels feed returns every video post; popular adds discovery.
    // Merge, dedupe by id, keep only titled videos, newest first.
    final results = await Future.wait([
      api.feed.reelsFeed().catchError((_) => <Post>[]),
      api.feed.popularReels().catchError((_) => <Post>[]),
    ]);
    final seen = <String>{};
    final out = <Post>[];
    for (final list in results) {
      for (final p in list) {
        if (_isVideoPost(p) && seen.add(p.id)) out.add(p);
      }
    }
    return out;
  }

  Future<void> _reload() async {
    setState(() => _videos = _load());
    await _videos;
  }

  Future<void> _upload() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const VideoComposerScreen()),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Videos'),
        actions: [
          IconButton(
            tooltip: 'Upload a video',
            icon: const Icon(Icons.video_call_outlined),
            onPressed: _upload,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        icon: const Icon(Icons.upload),
        label: const Text('Upload'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<Post>>(
            future: _videos,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return CenteredMessage(
                    message: messageFor(snap.error),
                    icon: Icons.error_outline,
                    onRetry: _reload);
              }
              final videos = snap.data ?? const <Post>[];
              if (videos.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 120),
                    Icon(Icons.smart_display_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    const Center(child: Text('No videos yet.')),
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.icon(
                        onPressed: _upload,
                        icon: const Icon(Icons.upload),
                        label: const Text('Upload a video'),
                      ),
                    ),
                  ],
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: videos.length,
                itemBuilder: (context, i) => _VideoCard(
                  post: videos[i],
                  onTap: () => _openWatch(videos, i),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openWatch(List<Post> videos, int index) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoWatchScreen(videos: videos, index: index),
    ));
    if (mounted) _reload();
  }
}

/// One YouTube-style card: a 16:9 thumbnail with a play overlay, then a row
/// of channel avatar + title/metadata.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = _videoOf(post);
    final thumb = media?.thumbnail;
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumb != null && thumb.isNotEmpty)
                  Image.network(thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: scheme.surfaceContainerHighest))
                else
                  ColoredBox(color: scheme.surfaceContainerHighest),
                const Center(
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.black45,
                    child: Icon(Icons.play_arrow, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(
                    url: post.author.picture,
                    name: post.author.name,
                    radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                          '${post.author.name} · '
                          '${formatCount(post.viewsCount)} views · '
                          '${shortAgo(post.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.outline, fontSize: 12.5)),
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

/// YouTube-style watch page: a 16:9 player on top, then title, stats,
/// channel row, actions, description, and an "Up next" list.
class VideoWatchScreen extends StatefulWidget {
  const VideoWatchScreen({super.key, required this.videos, required this.index});

  final List<Post> videos;
  final int index;

  @override
  State<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

class _VideoWatchScreenState extends State<VideoWatchScreen> {
  late int _index = widget.index;
  late Post _post = widget.videos[_index];
  bool _expanded = false;
  bool _liked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _liked = _post.likedByMe;
    _recordView();
  }

  void _recordView() {
    api.feed.recordView(_post.id).catchError((_) {});
  }

  void _play(int i) {
    if (i < 0 || i >= widget.videos.length) return;
    setState(() {
      _index = i;
      _post = widget.videos[i];
      _liked = _post.likedByMe;
      _expanded = false;
    });
    _recordView();
  }

  Future<void> _like() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _liked = !_liked;
    });
    try {
      await api.feed.toggleLike(_post.id);
    } catch (e) {
      if (mounted) {
        setState(() => _liked = !_liked);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    try {
      await api.feed.toggleBookmark(_post.id);
      if (mounted) showInfo(context, 'Saved to your bookmarks');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _share() async {
    await Clipboard.setData(
        ClipboardData(text: 'https://okayspace.ca/p/${_post.id}'));
    if (mounted) showInfo(context, 'Video link copied');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = _videoOf(_post)!;
    final upNext = [
      for (var i = 0; i < widget.videos.length; i++)
        if (i != _index) (i, widget.videos[i]),
    ];
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Watch')),
      body: MaxWidth(
        child: ListView(
          children: [
            // Player — keyed by id so switching videos rebuilds it cleanly.
            AspectRatio(
              aspectRatio: 16 / 9,
              child: PostVideo(
                key: ValueKey(_post.id),
                url: media.url!,
                poster: media.thumbnail,
                autoPlay: true,
                resolveOnError: () async {
                  final r =
                      await api.client.postJson('/media/resolve-video', body: {
                    'url': media.url,
                  });
                  return r is Map ? '${r['url'] ?? media.url}' : media.url!;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_post.title ?? 'Video',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      '${formatCount(_post.viewsCount)} views · '
                      '${shortAgo(_post.createdAt)}',
                      style: TextStyle(color: scheme.outline, fontSize: 13)),
                  const SizedBox(height: 12),
                  // Action row: like, save, share.
                  Row(
                    children: [
                      _ActionButton(
                        icon: _liked
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                        label: formatCount(
                            _post.likesCount + (_liked && !_post.likedByMe
                                ? 1
                                : (!_liked && _post.likedByMe ? -1 : 0))),
                        active: _liked,
                        onTap: _busy ? null : _like,
                      ),
                      _ActionButton(
                        icon: Icons.bookmark_border,
                        label: 'Save',
                        onTap: _save,
                      ),
                      _ActionButton(
                        icon: Icons.share_outlined,
                        label: 'Share',
                        onTap: _share,
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  // Channel row.
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(userId: _post.author.userId))),
                    child: Row(
                      children: [
                        Avatar(
                            url: _post.author.picture,
                            name: _post.author.name,
                            radius: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_post.author.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                              if (_post.author.username != null)
                                Text('@${_post.author.username}',
                                    style: TextStyle(
                                        color: scheme.outline, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        if (_post.author.userId != currentUserId)
                          _SubscribeButton(userId: _post.author.userId),
                      ],
                    ),
                  ),
                  if ((_post.text).trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_post.text,
                              maxLines: _expanded ? null : 3,
                              overflow: _expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                PostDetailScreen(post: _post))),
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: const Text('Comments'),
                  ),
                ],
              ),
            ),
            if (upNext.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Up next',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final (i, p) in upNext)
                _UpNextTile(post: p, onTap: () => _play(i)),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Compact horizontal video row for the "Up next" list.
class _UpNextTile extends StatelessWidget {
  const _UpNextTile({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = _videoOf(post)?.thumbnail;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 160,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: thumb != null && thumb.isNotEmpty
                      ? Image.network(thumb,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                              color: scheme.surfaceContainerHighest))
                      : ColoredBox(color: scheme.surfaceContainerHighest),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title ?? 'Video',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(
                      '${post.author.name} · '
                      '${formatCount(post.viewsCount)} views',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: scheme.outline, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscribeButton extends StatefulWidget {
  const _SubscribeButton({required this.userId});
  final String userId;

  @override
  State<_SubscribeButton> createState() => _SubscribeButtonState();
}

class _SubscribeButtonState extends State<_SubscribeButton> {
  bool _following = false;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _following = !_following;
    });
    try {
      // follow() is a toggle on the backend.
      await api.users.follow(widget.userId);
    } catch (e) {
      if (mounted) {
        setState(() => _following = !_following);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _following
        ? OutlinedButton(
            onPressed: _toggle, child: const Text('Subscribed'))
        : FilledButton(onPressed: _toggle, child: const Text('Subscribe'));
  }
}

/// YouTube-style upload: pick a video, give it a title + description, it
/// uploads to Cloudinary and posts as a titled video.
class VideoComposerScreen extends StatefulWidget {
  const VideoComposerScreen({super.key});

  @override
  State<VideoComposerScreen> createState() => _VideoComposerScreenState();
}

class _VideoComposerScreenState extends State<VideoComposerScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  Uint8List? _bytes;
  String? _fileName;
  bool _busy = false;

  // Keep video uploads sane for the data-URI upload path.
  static const _maxBytes = 200 * 1024 * 1024; // 200 MB

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxBytes) {
        if (mounted) {
          showInfo(context, 'That video is over 200 MB — pick a shorter one.');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _fileName = file.name;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _publish() async {
    final bytes = _bytes;
    final title = _title.text.trim();
    if (bytes == null) {
      showInfo(context, 'Pick a video first.');
      return;
    }
    if (title.isEmpty) {
      showInfo(context, 'Give your video a title.');
      return;
    }
    if (!hasCloudinary) {
      showInfo(context,
          'Video hosting isn\'t configured on this build (CLOUDINARY_*).');
      return;
    }
    setState(() => _busy = true);
    try {
      final up = await cloudinaryUploadVideo(bytes, folder: 'videos');
      if (up.url == null) {
        if (mounted) {
          showInfo(context, 'Upload failed — please try again.');
        }
        return;
      }
      await api.feed.createPost(PostCreate(
        text: _description.text.trim(),
        title: title,
        media: [
          PostMedia(
            type: 'video',
            url: up.url,
            thumbnail: up.thumbnail,
            width: up.width,
            height: up.height,
          ),
        ],
      ));
      if (mounted) {
        showInfo(context, 'Video published 🎬');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Upload video')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Video picker / preview tile.
            InkWell(
              onTap: _busy ? null : _pick,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 170,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          _bytes == null
                              ? Icons.video_call_outlined
                              : Icons.check_circle,
                          size: 40,
                          color: scheme.primary),
                      const SizedBox(height: 8),
                      Text(_bytes == null
                          ? 'Tap to choose a video'
                          : (_fileName ?? 'Video selected')),
                      if (_bytes != null)
                        Text(
                            '${(_bytes!.length / (1024 * 1024)).toStringAsFixed(1)} MB',
                            style: TextStyle(
                                color: scheme.outline, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Add a title that describes your video',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload),
              label: Text(_busy ? 'Uploading…' : 'Publish'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Large videos can take a minute to upload.',
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
