import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';
import 'profile_screen.dart';

Color _communityColor(Community c, BuildContext context) {
  final hex = c.color.replaceFirst('#', '');
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return Theme.of(context).colorScheme.primary;
}

/// Browse and search communities.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  late Future<List<Community>> _communities;
  late Future<List<Post>> _feed;
  final _search = TextEditingController();
  String? _sort;

  @override
  void initState() {
    super.initState();
    _query();
    _feed = api.communities.feed();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _query() {
    final q = _search.text.trim();
    _communities =
        api.communities.list(query: q.isEmpty ? null : q, sort: _sort);
  }

  Future<void> _reload() async {
    setState(() {
      _query();
      _feed = api.communities.feed();
    });
    await _communities;
  }

  Future<void> _pickSort() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Sort communities',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final s in const [
              ('Popular', 'popular'),
              ('Newest', 'new'),
              ('Most active', 'active'),
            ])
              ListTile(
                title: Text(s.$1),
                trailing: s.$2 == _sort ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, s.$2),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      _sort = chosen;
      _query();
    });
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateCommunityDialog(),
    );
    if (name == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(name: name),
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: OkayAppBar(
          title: const Text('Communities'),
          actions: [
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              onPressed: _pickSort,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Create community',
              onPressed: _create,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(104),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _reload(),
                    decoration: InputDecoration(
                      hintText: 'Search communities',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: _reload),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const TabBar(
                  tabs: [Tab(text: 'Discover'), Tab(text: 'My feed')],
                ),
              ],
            ),
          ),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [_discover(), _myFeed()],
          ),
        ),
      ),
    );
  }

  Widget _discover() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<Community>(
        future: _communities,
        loading: const ListSkeleton(),
        emptyMessage: 'No communities found.',
        emptyIcon: Icons.groups_outlined,
        builder: (context, items) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          itemCount: items.length,
          itemBuilder: (context, i) =>
              _CommunityCard(community: items[i], onChanged: _reload),
        ),
      ),
    );
  }

  Widget _myFeed() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<Post>(
        future: _feed,
        loading: const FeedSkeleton(),
        emptyMessage: 'Join communities to see their posts here.',
        emptyIcon: Icons.dynamic_feed_outlined,
        builder: (context, items) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: items.length,
          itemBuilder: (context, i) => PostTile(post: items[i], card: true),
        ),
      ),
    );
  }
}

/// A discover-list community card: avatar, stats, description preview and
/// inline favorite + join actions (optimistic).
class _CommunityCard extends StatefulWidget {
  const _CommunityCard({required this.community, required this.onChanged});

  final Community community;
  final VoidCallback onChanged;

  @override
  State<_CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends State<_CommunityCard> {
  late bool _member = widget.community.isMember;
  late bool _favorite = widget.community.isFavorite;
  late int _members = widget.community.memberCount;

  Community get c => widget.community;

  Future<void> _join() async {
    final was = _member;
    setState(() {
      _member = !_member;
      _members += _member ? 1 : -1;
    });
    try {
      was ? await api.communities.leave(c.name) : await api.communities.join(c.name);
      widget.onChanged();
    } catch (e) {
      setState(() {
        _member = was;
        _members += was ? 1 : -1;
      });
      if (mounted) showError(context, e);
    }
  }

  Future<void> _favoriteToggle() async {
    final was = _favorite;
    setState(() => _favorite = !_favorite);
    try {
      was
          ? await api.communities.unfavorite(c.name)
          : await api.communities.favorite(c.name);
    } catch (e) {
      setState(() => _favorite = was);
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _communityColor(c, context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CommunityDetailScreen(name: c.name),
        )),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: color,
                    child: Text(
                      c.title.isNotEmpty ? c.title[0].toUpperCase() : '#',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.title.isNotEmpty ? c.title : 'c/${c.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                            '${formatCount(_members)} members · ${formatCount(c.postCount)} posts',
                            style: TextStyle(
                                color: scheme.outline, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _favorite ? 'Unfavorite' : 'Favorite',
                    icon: Icon(_favorite ? Icons.star : Icons.star_border,
                        color: _favorite
                            ? const Color(0xFFF59E0B)
                            : scheme.outline),
                    onPressed: _favoriteToggle,
                  ),
                ],
              ),
              if (c.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(c.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _member
                    ? OutlinedButton.icon(
                        onPressed: _join,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Joined'),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: _join,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Join community'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A community's header (with join/leave) and its posts.
class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({super.key, required this.name});

  final String name;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  late Future<Community> _community;
  late Future<List<Post>> _posts;
  bool _working = false;
  String _sort = 'hot';

  static const _sorts = <(String, IconData)>[
    ('hot', Icons.local_fire_department),
    ('new', Icons.fiber_new),
    ('top', Icons.emoji_events),
    ('rising', Icons.trending_up),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _community = api.communities.get(widget.name);
    _posts = api.communities.posts(widget.name, sort: _sort);
  }

  void _setSort(String s) {
    if (s == _sort) return;
    setState(() {
      _sort = s;
      _posts = api.communities.posts(widget.name, sort: _sort);
    });
  }

  Future<void> _reload() async {
    setState(_load);
    await _community;
  }

  Future<void> _toggleMembership(Community c) async {
    setState(() => _working = true);
    try {
      if (c.isMember) {
        await api.communities.leave(c.name);
      } else {
        await api.communities.join(c.name);
      }
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _composePost() async {
    final text = await promptText(context,
        title: 'Post to c/${widget.name}', hint: "What's happening?");
    if (text == null) return;
    try {
      final c = await _community;
      await api.feed.createPost(PostCreate(text: text, communityId: c.id));
      if (mounted) {
        showInfo(context, 'Posted');
        setState(() => _posts = api.communities.posts(widget.name));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleFavorite(Community c) async {
    try {
      if (c.isFavorite) {
        await api.communities.unfavorite(c.name);
      } else {
        await api.communities.favorite(c.name);
      }
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// A small rounded stat chip (members / posts) for the header.
  Widget _statChip(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.outline),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Bottom sheet with the community's karma leaderboard.
  void _showLeaderboard() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => FutureBuilder<List<Map<String, dynamic>>>(
        future: api.communities.topMembers(widget.name),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
                height: 220, child: Center(child: CircularProgressIndicator()));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const SizedBox(
                height: 220,
                child: Center(child: Text('No karma earned here yet.')));
          }
          final scheme = Theme.of(context).colorScheme;
          const medals = [Color(0xFFF59E0B), Color(0xFF9CA3AF), Color(0xFFB45309)];
          return ListView.builder(
            shrinkWrap: true,
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const ListTile(
                    title: Text('Top karma',
                        style: TextStyle(fontWeight: FontWeight.bold)));
              }
              final m = items[i - 1];
              final rank = i;
              final name = '${m['name'] ?? m['username'] ?? 'Member'}';
              final karmaV = m['karma'] ?? m['points'] ?? m['score'];
              final karma = karmaV is num ? karmaV.toInt() : 0;
              final userId = '${m['user_id'] ?? m['id'] ?? ''}';
              return ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 26,
                      child: rank <= 3
                          ? Icon(Icons.emoji_events,
                              size: 20, color: medals[rank - 1])
                          : Text('$rank',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: scheme.outline,
                                  fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                    Avatar(url: '${m['picture'] ?? ''}', name: name, radius: 17),
                  ],
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👍 '),
                    Text(formatCount(karma),
                        style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                onTap: userId.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        ProfileScreen.open(context, userId);
                      },
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: Text('c/${widget.name}'),
        actions: [
          FutureBuilder<Community>(
            future: _community,
            builder: (context, snap) {
              final c = snap.data;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c != null)
                    IconButton(
                      tooltip: c.isFavorite ? 'Unfavorite' : 'Favorite',
                      icon: Icon(
                          c.isFavorite ? Icons.star : Icons.star_border,
                          color: c.isFavorite
                              ? const Color(0xFFF59E0B)
                              : null),
                      onPressed: () => _toggleFavorite(c),
                    ),
                  IconButton(
                    tooltip: 'Karma leaderboard',
                    icon: const Icon(Icons.emoji_events_outlined),
                    onPressed: _showLeaderboard,
                  ),
                  IconButton(
                    tooltip: 'Members',
                    icon: const Icon(Icons.people_outline),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CommunityMembersScreen(
                            name: widget.name,
                            canModerate: c?.canModerate ?? false),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _composePost,
        child: const Icon(Icons.edit),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            FutureBuilder<Community>(
              future: _community,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final c = snapshot.data!;
                final color = _communityColor(c, context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Colored banner with the community avatar overlapping it.
                    SizedBox(
                      height: 116,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 84,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, darken(color, 0.25)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).scaffoldBackgroundColor,
                              ),
                              child: CircleAvatar(
                                radius: 32,
                                backgroundColor: color,
                                child: Text(
                                  c.title.isNotEmpty
                                      ? c.title[0].toUpperCase()
                                      : '#',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 26),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        c.title.isNotEmpty
                                            ? c.title
                                            : 'c/${c.name}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold)),
                                    Text('c/${c.name}',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: _working
                                    ? null
                                    : () => _toggleMembership(c),
                                child: Text(c.isMember ? 'Leave' : 'Join'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Stat chips.
                          Row(
                            children: [
                              _statChip(context, Icons.people_outline,
                                  '${formatCount(c.memberCount)} members'),
                              const SizedBox(width: 8),
                              _statChip(context, Icons.article_outlined,
                                  '${formatCount(c.postCount)} posts'),
                            ],
                          ),
                      if (c.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(c.description),
                      ],
                      if (c.rules.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Rules',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        for (var r = 0; r < c.rules.length; r++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${r + 1}. ${c.rules[r]}',
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                          ),
                      ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 1),
            // Hot / New / Top / Rising sort chips.
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final (s, icon) in _sorts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(icon,
                            size: 16,
                            color: _sort == s
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.primary),
                        label: Text(s[0].toUpperCase() + s.substring(1)),
                        selected: _sort == s,
                        onSelected: (_) => _setSort(s),
                      ),
                    ),
                ],
              ),
            ),
            FutureBuilder<List<Post>>(
              future: _posts,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final posts = snapshot.data ?? const [];
                if (posts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No posts yet.')),
                  );
                }
                return Column(
                  children: [
                    for (final p in posts) PostTile(post: p, card: true),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Members of a community, with moderator actions for moderators.
class CommunityMembersScreen extends StatefulWidget {
  const CommunityMembersScreen(
      {super.key, required this.name, this.canModerate = false});

  final String name;
  final bool canModerate;

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  late Future<List<Map<String, dynamic>>> _members;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _members = api.communities.members(widget.name).then((d) {
      final list = d is Map
          ? (d['members'] ?? d['items'] ?? d['data'])
          : d;
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    });
  }

  Future<void> _reload() async {
    setState(_load);
    await _members;
  }

  Future<void> _modAction(
      String userId, Future<void> Function() op, String ok) async {
    try {
      await op();
      if (mounted) showInfo(context, ok);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Members')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _members,
            emptyMessage: 'No members yet.',
            emptyIcon: Icons.people_outline,
            builder: (context, items) => ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = items[i];
                final userId =
                    '${m['user_id'] ?? m['id'] ?? ''}';
                final name = '${m['name'] ?? m['username'] ?? 'Member'}';
                final role = '${m['role'] ?? ''}';
                final isMod = role == 'moderator' || role == 'owner' ||
                    m['is_moderator'] == true;
                return ListTile(
                  leading: Avatar(
                      url: '${m['picture'] ?? ''}', name: name),
                  title: Text(name),
                  subtitle: role.isNotEmpty ? Text(role) : null,
                  trailing: widget.canModerate && userId.isNotEmpty
                      ? PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'mod') {
                              _modAction(
                                  userId,
                                  () => api.communities
                                      .addModerator(widget.name, userId),
                                  'Promoted to moderator');
                            } else if (v == 'unmod') {
                              _modAction(
                                  userId,
                                  () => api.communities
                                      .removeModerator(widget.name, userId),
                                  'Removed moderator');
                            } else if (v == 'remove') {
                              _modAction(
                                  userId,
                                  () => api.communities
                                      .removeMember(widget.name, userId),
                                  'Removed member');
                            }
                          },
                          itemBuilder: (_) => [
                            if (!isMod)
                              const PopupMenuItem(
                                  value: 'mod',
                                  child: Text('Make moderator')),
                            if (isMod)
                              const PopupMenuItem(
                                  value: 'unmod',
                                  child: Text('Remove moderator')),
                            const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from community')),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateCommunityDialog extends StatefulWidget {
  const _CreateCommunityDialog();

  @override
  State<_CreateCommunityDialog> createState() => _CreateCommunityDialogState();
}

class _CreateCommunityDialogState extends State<_CreateCommunityDialog> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final c = await api.communities.create(
        name: name,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      if (mounted) Navigator.pop(context, c.name);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create community'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name (no spaces)',
                prefixText: 'c/',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Display title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}
