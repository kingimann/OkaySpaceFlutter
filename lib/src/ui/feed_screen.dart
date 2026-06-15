import 'dart:async';

import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'app_drawer.dart';
import 'common.dart';
import 'feed_prefs.dart';
import 'compose_screen.dart';
import 'hashtag_screen.dart';
import 'post_tile.dart';

/// Home feed: a post list with a composer.
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
    homeTabSignal.addListener(_onHomeTab);
    // Poll for newer posts so a "new posts" pill can appear.
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _checkNew());
  }

  bool _appliedDefaultTab = false;
  String _lastTab = homeTabSignal.value;

  /// Refetch when the user switches back to the Feed tab from another tab, so
  /// posts that were removed (e.g. by AI moderation) drop out of the cached
  /// list instead of lingering. Re-tapping Feed while already on it is handled
  /// by [feedScrollSignal] (scroll-to-top + reload).
  void _onHomeTab() {
    final tab = homeTabSignal.value;
    final switchedToFeed = tab == 'feed' && _lastTab != 'feed';
    _lastTab = tab;
    if (switchedToFeed && mounted) _reload();
  }

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
    homeTabSignal.removeListener(_onHomeTab);
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
              // Messages, Notifications, Search etc. now live in the right
              // sidebar — open it from here (keeps the unread badge).
              IconButton(
                tooltip: 'Shortcuts',
                onPressed: () => homeScaffoldKey.currentState?.openEndDrawer(),
                icon: _unread > 0
                    ? Badge(
                        label: Text('$_unread'), child: const Icon(Icons.apps))
                    : const Icon(Icons.apps),
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
