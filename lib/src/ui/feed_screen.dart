import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'notifications_screen.dart';
import 'post_tile.dart';
import 'search_screen.dart';
import 'story_composer.dart';
import 'story_viewer.dart';

/// Home feed: a story tray followed by the post list, with a composer.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Post>> _feed;
  late Future<List<StoryTrayItem>> _stories;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _feed = api.feed.homeFeed();
    _stories = api.stories.tray();
    api.notifications.unreadCount().then((count) {
      if (mounted) setState(() => _unread = count);
    }).catchError((_) {});
  }

  Future<void> _addStory() async {
    final posted = await StoryComposer.start(context);
    if (posted && mounted) {
      setState(() => _stories = api.stories.tray());
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const NotificationsScreen(),
    ));
    final count = await api.notifications.unreadCount().catchError((_) => 0);
    if (mounted) setState(() => _unread = count);
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
      appBar: AppBar(
        title: const Text('OkaySpace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SearchScreen(),
            )),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: _unread > 0
                ? Badge(label: Text('$_unread'), child: const Icon(Icons.notifications_none))
                : const Icon(Icons.notifications_none),
          ),
        ],
      ),
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
              return const FeedSkeleton();
            }
            if (snapshot.hasError) {
              return CenteredMessage(
                message: 'Could not load feed.\n${messageFor(snapshot.error)}',
                icon: Icons.cloud_off_outlined,
                onRetry: _reload,
              );
            }
            final posts = snapshot.data ?? const [];
            return ListView.separated(
              itemCount: posts.length + 1,
              separatorBuilder: (_, i) =>
                  i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Column(
                    children: [
                      _StoryTray(future: _stories, onAdd: _addStory),
                      if (posts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 100),
                          child: Column(
                            children: [
                              Icon(Icons.dynamic_feed_outlined,
                                  size: 56,
                                  color:
                                      Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 12),
                              Text('Your feed is empty.\nTap the pencil to post.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline)),
                            ],
                          ),
                        ),
                    ],
                  );
                }
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
  const _StoryTray({required this.future, required this.onAdd});

  final Future<List<StoryTrayItem>> future;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoryTrayItem>>(
      future: future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <StoryTrayItem>[];
        return Container(
          height: 104,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            // First cell is the "add your story" button.
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _AddStoryTile(onTap: onAdd);
              return _StoryTrayTile(item: items[i - 1]);
            },
          ),
        );
      },
    );
  }
}

class _AddStoryTile extends StatelessWidget {
  const _AddStoryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(Icons.add, color: scheme.primary),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 64,
              child: Text('Your story',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryTrayTile extends StatelessWidget {
  const _StoryTrayTile({required this.item});

  final StoryTrayItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: () => StoryViewerScreen.open(context, item.userId, item.userName),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.hasUnviewed
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                child: Avatar(
                    url: item.userPicture, name: item.userName, radius: 26),
              ),
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
      ),
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
