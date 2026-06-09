import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';

/// Home feed: a story tray followed by the post list, with a composer.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Post>> _feed;
  late Future<List<StoryTrayItem>> _stories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _feed = api.feed.homeFeed();
    _stories = api.stories.tray();
  }

  Future<void> _reload() async {
    setState(_load);
    await _feed;
  }

  Future<void> _compose() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ComposeDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await api.feed.post(text.trim());
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleLike(Post post) async {
    try {
      await api.feed.toggleLike(post.id);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        child: const Icon(Icons.edit),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Post>>(
          future: _feed,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return CenteredMessage(
                message: 'Could not load feed.\n${messageFor(snapshot.error)}',
                onRetry: _reload,
              );
            }
            final posts = snapshot.data ?? const [];
            return ListView.separated(
              itemCount: posts.length + 1,
              separatorBuilder: (_, i) =>
                  i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) return _StoryTray(future: _stories);
                final post = posts[i - 1];
                return PostTile(post: post, onLike: () => _toggleLike(post));
              },
            );
          },
        ),
      ),
    );
  }
}

class _StoryTray extends StatelessWidget {
  const _StoryTray({required this.future});

  final Future<List<StoryTrayItem>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoryTrayItem>>(
      future: future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Container(
          height: 100,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 2.5,
                          color: item.hasUnviewed
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Avatar(
                          url: item.userPicture,
                          name: item.userName,
                          radius: 28),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: Text(
                        item.userName,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog();

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New post'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: "What's happening?",
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Post'),
        ),
      ],
    );
  }
}
