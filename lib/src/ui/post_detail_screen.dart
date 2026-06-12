import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';
import 'post_video.dart';
import 'profile_screen.dart';

/// A single post shown in full with its replies and a reply composer.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  static Future<void> open(BuildContext context, Post post) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post),
      ));

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Post _post;
  late Future<List<Post>> _replies;
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _replies = api.feed.replies(_post.id);
    // Refresh the post itself for up-to-date counts.
    api.feed.getPost(_post.id).then((p) {
      if (mounted) setState(() => _post = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reloadReplies() async {
    setState(() => _replies = api.feed.replies(_post.id));
    await _replies;
  }

  Future<void> _toggleLike() async {
    try {
      final updated = await api.feed.toggleLike(_post.id);
      if (mounted) setState(() => _post = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleDislike() async {
    try {
      final updated = await api.feed.toggleDislike(_post.id);
      if (mounted) setState(() => _post = updated);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleRepost() async {
    try {
      final updated = await api.feed.toggleRepost(_post.id);
      if (mounted) {
        setState(() => _post = updated);
        showInfo(context, updated.repostedByMe ? 'Reposted' : 'Repost removed');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleBookmark() async {
    try {
      final updated = await api.feed.toggleBookmark(_post.id);
      if (mounted) {
        setState(() => _post = updated);
        showInfo(context,
            updated.bookmarkedByMe ? 'Bookmarked' : 'Removed bookmark');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Repost button → choose between a plain repost and a quote.
  Future<void> _repostMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(_post.repostedByMe ? 'Undo repost' : 'Repost'),
              onTap: () => Navigator.pop(context, 'repost'),
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('Quote'),
              onTap: () => Navigator.pop(context, 'quote'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'repost') {
      await _toggleRepost();
    } else if (choice == 'quote') {
      await _quote();
    }
  }

  Future<void> _quote() async {
    final controller = TextEditingController();
    final String? text;
    try {
      text = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Quote post'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'Add a comment', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Post')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (text == null || text.trim().isEmpty) return;
    try {
      await api.feed.createPost(PostCreate(text: text.trim(), quoteOf: _post.id));
      if (mounted) showInfo(context, 'Quoted');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sendReply() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await api.feed.reply(_post.id, text);
      _input.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _reloadReplies();
      // Bump the local reply count.
      api.feed.getPost(_post.id).then((p) {
        if (mounted) setState(() => _post = p);
      }).catchError((_) {});
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Post')),
      body: MaxWidth(
        child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reloadReplies,
              child: ListView(
                children: [
                  _PostHeader(
                    post: _post,
                    onLike: _toggleLike,
                    onDislike: _toggleDislike,
                    onRepost: _repostMenu,
                    onBookmark: _toggleBookmark,
                  ),
                  const Divider(height: 1, thickness: 6),
                  FutureBuilder<List<Post>>(
                    future: _replies,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                              child: Text(messageFor(snapshot.error))),
                        );
                      }
                      final replies = snapshot.data ?? const [];
                      if (replies.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No replies yet.')),
                        );
                      }
                      return Column(
                        children: [
                          for (final r in replies) ...[
                            PostTile(post: r),
                            const Divider(height: 1),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendReply(),
                      decoration: const InputDecoration(
                        hintText: 'Post your reply',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _sendReply,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The focused post, rendered larger than a feed row.
class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.post,
    required this.onLike,
    required this.onDislike,
    required this.onRepost,
    required this.onBookmark,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onRepost;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    final muted = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => ProfileScreen.open(context, author.userId),
                child: Avatar(url: author.picture, name: author.name),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(author.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ),
                        if (author.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 16, color: Colors.blue),
                        ],
                      ],
                    ),
                    if (author.username != null)
                      Text('@${author.username}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (post.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(post.text, style: const TextStyle(fontSize: 17)),
          ],
          // Full media, regardless of the feed's data-saver preference —
          // the collapsed "tap to view" chips land here.
          for (final m in post.media)
            if (m.url != null && m.url!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: m.isVideo
                        ? PostVideo(url: m.url!)
                        : Image.network(m.url!, fit: BoxFit.cover),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Text(
            '${post.createdAt.toLocal()}'.split('.').first,
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            children: [
              _Stat(value: post.repliesCount, label: 'Replies'),
              _Stat(value: post.repostsCount, label: 'Reposts'),
              _Stat(value: post.likesCount, label: 'Likes'),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                tooltip: 'Like',
                onPressed: onLike,
                icon: Icon(
                  post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: post.likedByMe ? Colors.red : muted,
                ),
              ),
              IconButton(
                tooltip: 'Dislike',
                onPressed: onDislike,
                icon: Icon(
                  post.dislikedByMe
                      ? Icons.thumb_down
                      : Icons.thumb_down_outlined,
                  color: post.dislikedByMe
                      ? Theme.of(context).colorScheme.primary
                      : muted,
                ),
              ),
              IconButton(
                tooltip: 'Reply',
                onPressed: null,
                icon: Icon(Icons.mode_comment_outlined, color: muted),
              ),
              IconButton(
                tooltip: 'Repost',
                onPressed: onRepost,
                icon: Icon(Icons.repeat,
                    color: post.repostedByMe
                        ? Theme.of(context).colorScheme.primary
                        : muted),
              ),
              IconButton(
                tooltip: 'Bookmark',
                onPressed: onBookmark,
                icon: Icon(
                  post.bookmarkedByMe ? Icons.bookmark : Icons.bookmark_border,
                  color: post.bookmarkedByMe
                      ? Theme.of(context).colorScheme.primary
                      : muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Row(
        children: [
          Text(formatCount(value),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}
