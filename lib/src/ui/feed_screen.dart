import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'app_drawer.dart';
import 'common.dart';
import 'compose_screen.dart';
import 'hashtag_screen.dart';
import 'map_screen.dart';
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
  late Future<List<Map<String, dynamic>>> _trending;
  int _unread = 0;
  int _tab = 0; // 0 = Explore, 1 = Following, 2 = Popular
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    feedScrollSignal.addListener(_onScrollToTop);
  }

  @override
  void dispose() {
    feedScrollSignal.removeListener(_onScrollToTop);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _reload();
  }

  void _load() {
    _feed = switch (_tab) {
      1 => api.feed.homeFeed(),
      2 => api.feed.popularPosts(),
      _ => api.feed.exploreFeed(),
    };
    _stories = api.stories.tray();
    _trending = api.feed.trendingHashtags();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: MaxWidth(
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
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: posts.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Column(
                            children: [
                              _ComposerPrompt(onTap: _compose),
                              _StoryTray(future: _stories, onAdd: _addStory),
                              _TrendingStrip(future: _trending),
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
                            post: post, card: true, onChanged: _reload);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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
                icon: const Icon(Icons.map_outlined),
                tooltip: 'Map',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MapScreen(),
                )),
              ),
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
                  const SizedBox(width: 8),
                  _tabChip('Popular', 2),
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

/// A tappable "What's on your mind?" prompt that opens the composer.
class _ComposerPrompt extends StatelessWidget {
  const _ComposerPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Avatar(url: null, name: '?', radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text("What's on your mind?",
                      style: TextStyle(color: scheme.outline)),
                ),
                Icon(Icons.image_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 12),
                Icon(Icons.poll_outlined, color: scheme.primary, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal strip of trending hashtags below the composer.
class _TrendingStrip extends StatelessWidget {
  const _TrendingStrip({required this.future});

  final Future<List<Map<String, dynamic>>> future;

  String _tagOf(Map<String, dynamic> m) =>
      '${m['tag'] ?? m['name'] ?? m['hashtag'] ?? ''}'.replaceFirst('#', '');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        final tags = [
          for (final m in (snapshot.data ?? const []))
            if (_tagOf(m).isNotEmpty) _tagOf(m)
        ];
        if (tags.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(children: [
                  Icon(Icons.trending_up, size: 16, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text('Trending',
                      style: TextStyle(
                          color: scheme.outline,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              for (final t in tags.take(12))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('#$t'),
                    onPressed: () => HashtagScreen.open(context, t),
                  ),
                ),
            ],
          ),
        );
      },
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
