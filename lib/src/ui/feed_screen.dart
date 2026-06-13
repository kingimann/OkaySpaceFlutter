import 'dart:async';

import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'app_drawer.dart';
import 'common.dart';
import 'feed_prefs.dart';
import 'compose_screen.dart';
import 'hashtag_screen.dart';
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

  // Raw fetched posts + the one fetched ad, so preference changes re-filter
  // locally instead of refetching (and re-billing an ad impression).
  List<Post> _rawPosts = const [];
  Post? _ad;
  late Future<List<StoryTrayItem>> _stories;
  late Future<List<Map<String, dynamic>>> _trending;
  int _unread = 0;
  int _tab = 0; // 0 = Explore, 1 = Following, 2 = Popular
  final _scrollController = ScrollController();
  // Measured height of the floating header, used to inset the list beneath it.
  double _headerHeight = 124;
  // Live new-post polling + the floating "new posts" pill.
  Timer? _poll;
  String? _topPostId;
  bool _hasNewPosts = false;

  @override
  void initState() {
    super.initState();
    // Decide the starting tab BEFORE the single initial load; when prefs are
    // already loaded the default-tab logic is settled here, so a later pref
    // change can never yank the user between tabs.
    if (feedPrefs.isLoaded) {
      _appliedDefaultTab = true;
      if (feedPrefs.defaultTab == 'following') _tab = 1;
    }
    _load();
    feedPrefs.addListener(_onPrefsChanged);
    feedScrollSignal.addListener(_onScrollToTop);
    // Poll for newer posts so a "new posts" pill can appear.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _checkNew());
  }

  bool _appliedDefaultTab = false;

  void _onPrefsChanged() {
    if (!mounted) return;
    // First load may arrive after initState: apply the starting tab once.
    if (!_appliedDefaultTab && feedPrefs.isLoaded) {
      _appliedDefaultTab = true;
      if (feedPrefs.defaultTab == 'following' && _tab == 0) {
        setState(() {
          _tab = 1;
          _load();
        });
        return;
      }
    }
    // Re-filter the cached posts locally — no network, no skeleton flash,
    // no duplicate ad impressions. Guard: if the raw posts haven't loaded
    // yet (the prefs-storage load can notify mid-fetch), don't replace the
    // in-flight network future with an empty list — that left the feed
    // permanently blank until a manual reload.
    if (_rawPosts.isEmpty) return;
    setState(() => _feed = Future.value(_applyPrefs()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    feedPrefs.removeListener(_onPrefsChanged);
    feedScrollSignal.removeListener(_onScrollToTop);
    _scrollController.dispose();
    super.dispose();
  }

  /// Silently checks whether newer posts exist than the top of the list.
  Future<void> _checkNew() async {
    if (_hasNewPosts) return;
    try {
      final base = _tab == 1 ? api.feed.homeFeed() : api.feed.exploreFeed();
      // Compare like with like: the same preference filters as the display,
      // and newest-by-date (sort-independent) — otherwise a filtered-out or
      // top-sorted head produces a phantom "New posts" pill forever.
      final newest = _newestId(_filterPosts(await base));
      if (mounted && newest != null && newest != _topPostId) {
        setState(() => _hasNewPosts = true);
      }
    } catch (_) {/* ignore poll errors */}
  }

  /// The user's Customize-feed filters, applied to a raw post list.
  List<Post> _filterPosts(List<Post> list) {
    var out = list;
    if (feedPrefs.hideReposts) {
      out = out.where((p) => p.repostOf == null).toList();
    }
    if (feedPrefs.hidePolls) {
      out = out.where((p) => p.poll == null).toList();
    }
    if (feedPrefs.mutedAuthors.isNotEmpty) {
      out = out
          .where((p) => !feedPrefs.isAuthorMuted(p.author.userId))
          .toList();
    }
    if (feedPrefs.hideSponsored) {
      out = out.where((p) => !p.promoted).toList();
    }
    return out;
  }

  /// Id of the newest post by date (display-order independent).
  String? _newestId(List<Post> posts) => posts.isEmpty
      ? null
      : posts
          .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b)
          .id;

  /// Filters + orders the cached raw posts and weaves in the fetched ad.
  List<Post> _applyPrefs() {
    final filtered = _filterPosts(_rawPosts);
    _topPostId = _newestId(filtered);
    var out = _orderFeed(filtered);
    final ad = _ad;
    if (!feedPrefs.hideSponsored &&
        ad != null &&
        out.length >= 3 &&
        !out.any((p) => p.id == ad.id)) {
      out = [...out]..insert(out.length >= 4 ? 4 : out.length, ad);
    }
    return out;
  }

  void _loadNewPosts() {
    setState(() => _hasNewPosts = false);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _reload();
  }

  void _onScrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _reload();
  }

  void _load() {
    // 0 = Explore, 1 = Following.
    _hasNewPosts = false;
    final base = _tab == 1 ? api.feed.homeFeed() : api.feed.exploreFeed();
    _ad = null; // each network load may pick a fresh ad
    _feed = base.then((list) async {
      _rawPosts = list;
      // Fetch the ad only when sponsored content will be shown — fetching
      // records a billable impression.
      if (!feedPrefs.hideSponsored && list.length >= 3) {
        _ad = await _fetchAd(list);
      }
      return _applyPrefs();
    });
    _stories = api.stories.tray();
    _trending = api.feed.trendingHashtags();
    api.notifications.unreadCount().then((count) {
      if (mounted) setState(() => _unread = count);
    }).catchError((_) {});
  }

  /// Fetches one sponsored post for the feed slot (§3 AdSlot), recording an
  /// impression. Returns null when no ad is available or it's already shown.
  Future<Post?> _fetchAd(List<Post> list) async {
    try {
      final data = await api.ads.next(placement: 'feed');
      final raw = data['post'] is Map
          ? Map<String, dynamic>.from(data['post'] as Map)
          : data;
      if (raw.isEmpty) return null;
      final ad = Post.fromJson(raw);
      if (ad.id.isEmpty || list.any((p) => p.id == ad.id)) return null;
      api.ads.postEvent(ad.id, 'impression').ignore();
      return ad;
    } catch (_) {
      return null;
    }
  }

  /// Keeps sponsored posts pinned at the top, then orders the rest by the
  /// user's sort preference: newest first, or top engagement.
  List<Post> _orderFeed(List<Post> posts) {
    int engagement(Post p) =>
        p.likesCount + p.repostsCount + p.repliesCount + p.bookmarksCount;
    final promoted = posts.where((p) => p.promoted).toList();
    final rest = posts.where((p) => !p.promoted).toList()
      ..sort(feedPrefs.sort == 'top'
          ? (a, b) => engagement(b).compareTo(engagement(a))
          : (a, b) => b.createdAt.compareTo(a.createdAt));
    return [...promoted, ...rest];
  }

  void _setTab(int t) {
    if (t == _tab) return;
    _appliedDefaultTab = true; // a manual choice beats the default
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
      // Scrolling the drawer can hide the bars; a drawer isn't a route, so the
      // nav observer won't restore them — re-show them when it closes.
      onDrawerChanged: (open) {
        if (!open) showBars();
      },
      // The header floats over the list (content shows behind it) and slides
      // away on scroll, matching the floating bottom nav.
      body: MaxWidth(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: RefreshIndicator(
                onRefresh: _reload,
                edgeOffset: _headerHeight,
                child: FutureBuilder<List<Post>>(
                  future: _feed,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Padding(
                        padding: EdgeInsets.only(top: _headerHeight),
                        child: const FeedSkeleton(),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: EdgeInsets.only(top: _headerHeight),
                        child: CenteredMessage(
                          message:
                              'Could not load feed.\n${messageFor(snapshot.error)}',
                          icon: Icons.cloud_off_outlined,
                          onRetry: _reload,
                        ),
                      );
                    }
                    final posts = snapshot.data ?? const [];
                    return ListView.builder(
                      controller: _scrollController,
                      // Bottom inset clears the floating nav pill so the last
                      // card isn't hidden behind it on short feeds.
                      padding: EdgeInsets.only(
                          top: _headerHeight + 4, bottom: kBottomNavInset),
                      itemCount: posts.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Column(
                            children: [
                              ValueListenableBuilder<bool>(
                                valueListenable: hideStoriesController,
                                builder: (context, hidden, _) => hidden
                                    ? const SizedBox.shrink()
                                    : _StoryTray(
                                        future: _stories, onAdd: _addStory),
                              ),
                              if (feedPrefs.showTrending)
                                _TrendingStrip(future: _trending),
                              if (posts.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 48),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 84,
                                        height: 84,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.10),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.dynamic_feed_outlined,
                                            size: 40,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                          _tab == 1
                                              ? 'No posts from people you follow yet.'
                                              : 'Your feed is empty.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                              fontSize: 14.5,
                                              height: 1.35)),
                                      const SizedBox(height: 18),
                                      FilledButton.tonalIcon(
                                        onPressed: _compose,
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        label: const Text('Create a post'),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        }
                        final post = posts[i - 1];
                        return PostTile(
                            post: post,
                            card: !feedPrefs.compact,
                            onChanged: _reload);
                      },
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: barsT,
                builder: (context, t, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: t.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
                child: _MeasureSize(
                  onChange: (h) {
                    if (h != _headerHeight && mounted) {
                      setState(() => _headerHeight = h);
                    }
                  },
                  child: _buildHeader(context),
                ),
              ),
            ),
            // Floating "new posts" pill, shown when polling finds newer posts.
            if (_hasNewPosts)
              Positioned(
                top: _headerHeight + 4,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                    elevation: 3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _loadNewPosts,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_upward,
                                size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text('New posts',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
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
    return SafeArea(
      bottom: false,
      child: Container(
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
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Customize feed',
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const FeedPrefsScreen())),
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

  Widget _tabChip(String label, int idx) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _tab == idx;
    return GestureDetector(
      onTap: () => _setTab(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: selected ? scheme.onSurface : scheme.outline,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Reports its child's rendered height after layout, so the feed can inset the
/// list beneath the floating header without hard-coding its height.
class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});

  final ValueChanged<double> onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _key.currentContext?.size?.height;
      if (h != null) widget.onChange(h);
    });
    return SizedBox(key: _key, child: widget.child);
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
          child: Stack(
            children: [
              ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 8, 36, 8),
                // First cell is the "add your story" button.
                itemCount: items.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _AddStoryTile(onTap: onAdd);
                  return _StoryTrayTile(item: items[i - 1]);
                },
              ),
              // Lets the user hide the story tray from the feed (persisted;
              // re-enable from Settings).
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Hide stories',
                  icon: const Icon(Icons.close),
                  onPressed: () => hideStoriesController.set(true),
                ),
              ),
            ],
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
                // Unviewed stories get a vivid gradient ring; viewed ones a
                // flat muted ring.
                gradient: item.hasUnviewed
                    ? SweepGradient(colors: [
                        Theme.of(context).colorScheme.primary,
                        const Color(0xFFA855F7),
                        const Color(0xFFF97316),
                        Theme.of(context).colorScheme.primary,
                      ])
                    : null,
                color: item.hasUnviewed
                    ? null
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
