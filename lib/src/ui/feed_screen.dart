import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'app_drawer.dart';
import 'common.dart';
import 'compose_screen.dart';
import 'messages_screen.dart';
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
  int _tab = 0; // 0 = Explore, 1 = Following

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _feed = _tab == 0 ? api.feed.exploreFeed() : api.feed.homeFeed();
    _stories = api.stories.tray();
    api.notifications.unreadCount().then((count) {
      if (mounted) setState(() => _unread = count);
    }).catchError((_) {});
  }

  void _setTab(int t) {
    if (t == _tab) return;
    setState(() {
      _tab = t;
      _load();
    });
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
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const ComposeScreen(),
    ));
    if (posted == true) await _reload();
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
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: FutureBuilder<List<Post>>(
                  future: _feed,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const FeedSkeleton();
                    }
                    if (snapshot.hasError) {
                      return CenteredMessage(
                        message:
                            'Could not load feed.\n${messageFor(snapshot.error)}',
                        icon: Icons.cloud_off_outlined,
                        onRetry: _reload,
                      );
                    }
                    final posts = snapshot.data ?? const [];
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: posts.length + 1,
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
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline),
                                      const SizedBox(height: 12),
                                      Text('Your feed is empty.\nTap + to post.',
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
                        return PostTile(
                            post: post,
                            card: true,
                            onLike: () => _toggleLike(post));
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              Text('Feed',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SearchScreen(),
                )),
              ),
              GestureDetector(
                onTap: _compose,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ),
              IconButton(
                tooltip: 'Notifications',
                onPressed: _openNotifications,
                icon: _unread > 0
                    ? Badge(
                        label: Text('$_unread'),
                        child: const Icon(Icons.notifications_none))
                    : const Icon(Icons.notifications_none),
              ),
              IconButton(
                tooltip: 'Messages',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MessagesScreen(),
                )),
                icon: const Icon(Icons.forum_outlined),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabChip('Explore', 0),
                  const SizedBox(width: 8),
                  _tabChip('Following', 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int idx) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == idx;
    return GestureDetector(
      onTap: () => _setTab(idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? scheme.onSurface : scheme.outline,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            )),
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
