import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'app_drawer.dart';
import 'common.dart';
import 'connections_screen.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'post_tile.dart';
import 'settings_screen.dart';

/// Public profile of another user, with a follow toggle.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId});

  final String userId;

  /// Pushes this screen onto the navigator.
  static Future<void> open(BuildContext context, String userId) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ));

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<PublicUser> _profile;
  late Future<List<Post>> _posts;
  Future<List<Post>>? _likes;
  bool _following = false;
  // 0 Posts · 1 Media · 2 Likes
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _profile = _load();
    _posts = api.users.posts(widget.userId);
  }

  void _setTab(int t) {
    if (t == _tab) return;
    setState(() {
      _tab = t;
      if (t == 2) _likes ??= api.users.likes(widget.userId);
    });
  }

  Future<List<Post>> get _currentFuture =>
      _tab == 2 ? _likes! : _posts; // Posts and Media share the posts future

  int _stat(PublicUser u, List<String> keys) {
    final s = u.raw['stats'];
    if (s is Map) {
      for (final k in keys) {
        if (s[k] is num) return (s[k] as num).toInt();
      }
    }
    for (final k in keys) {
      if (u.raw[k] is num) return (u.raw[k] as num).toInt();
    }
    return 0;
  }

  Future<PublicUser> _load() async {
    final user = await api.users.publicProfile(widget.userId);
    _following = user.isFollowing;
    return user;
  }

  Future<void> _toggleFollow() async {
    setState(() => _following = !_following);
    try {
      await api.users.follow(widget.userId);
    } catch (e) {
      if (mounted) {
        setState(() => _following = !_following);
        showError(context, e);
      }
    }
  }

  Future<void> _message() async {
    try {
      final conv = await api.messaging.startDirect(widget.userId);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
            conversation: conv, title: conv.otherUser?.name ?? 'Chat'),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _showActions() async {
    final u = await _profile;
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined),
              title: const Text('Send a tip'),
              onTap: () => Navigator.pop(context, 'tip'),
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(u.raw['is_subscribed'] == true
                  ? 'Unsubscribe'
                  : 'Subscribe'),
              onTap: () => Navigator.pop(context, 'subscribe'),
            ),
            ListTile(
              leading: const Icon(Icons.waving_hand_outlined),
              title: const Text('Poke'),
              onTap: () => Navigator.pop(context, 'poke'),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Add friend'),
              onTap: () => Navigator.pop(context, 'friend'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'tip':
          await _tip();
        case 'subscribe':
          if (u.raw['is_subscribed'] == true) {
            await api.users.unsubscribe(widget.userId);
            if (mounted) showInfo(context, 'Unsubscribed');
          } else {
            await api.users.subscribe(widget.userId);
            if (mounted) showInfo(context, 'Subscribed');
          }
        case 'poke':
          await api.users.poke(widget.userId);
          if (mounted) showInfo(context, 'Poked ${u.name}');
        case 'friend':
          await api.friends.sendRequest(widget.userId);
          if (mounted) showInfo(context, 'Friend request sent');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _tip() async {
    final amountText = await promptText(context,
        title: 'Send a tip', hint: 'Amount', action: 'Send');
    final amount = num.tryParse(amountText ?? '');
    if (amount == null || amount <= 0) return;
    await api.users.tip(widget.userId, amount);
    if (mounted) showInfo(context, 'Tipped $amount 🎉');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const OkayBottomNav(),
      appBar: OkayAppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showActions,
          ),
        ],
      ),
      body: FutureBuilder<PublicUser>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CenteredMessage(
                message: messageFor(snapshot.error), icon: Icons.error_outline);
          }
          final u = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              MaxWidth(child: _profileCard(u)),
              const SizedBox(height: 12),
              MaxWidth(child: _postsSection()),
            ],
          );
        },
      ),
    );
  }

  /// Profile card mirroring My Profile: banner, avatar, name, level pill,
  /// info, stat cards and Follow/Message actions.
  Widget _profileCard(PublicUser u) {
    final scheme = Theme.of(context).colorScheme;
    final levelTitle = '${u.raw['level_title'] ?? ''}';
    final location = '${u.raw['location'] ?? ''}';
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, darken(scheme.primary, 0.25)],
                  ),
                ),
              ),
              Positioned(
                top: 56,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: Avatar(url: u.picture, name: u.name, radius: 42),
                ),
              ),
            ],
          ),
          const SizedBox(height: 52),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(u.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (u.verified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified, size: 20, color: Color(0xFF3B82F6)),
              ],
            ],
          ),
          if (u.username != null)
            Text(u.handle, style: TextStyle(color: scheme.primary)),
          const SizedBox(height: 12),
          if (u.points > 0 || u.level > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_fire_department,
                        color: scheme.primary, size: 18),
                    const SizedBox(width: 6),
                    Text('${u.points} points',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('Lv ${u.level}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(levelTitle,
                          style: TextStyle(color: scheme.outline)),
                    ),
                  ],
                ),
              ),
            ),
          if (u.headline != null && u.headline!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(u.headline!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (location.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.place_outlined, size: 16, color: scheme.outline),
              const SizedBox(width: 4),
              Text(location),
            ]),
          ],
          if (u.bio != null && u.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(u.bio!, textAlign: TextAlign.center),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _statsRow(u),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _toggleFollow,
                    child: Text(_following ? 'Following' : 'Follow'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _message,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(PublicUser u) {
    final scheme = Theme.of(context).colorScheme;
    final posts = _stat(u, ['posts', 'post_count', 'posts_count']);
    final followers =
        _stat(u, ['followers', 'followers_count', 'follower_count']);
    final following = _stat(u, ['following', 'following_count']);
    final friends = _stat(u, ['friends', 'friends_count', 'friend_count']);
    Widget cell(String label, int value, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text(formatCount(value),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
              ]),
            ),
          ),
        );
    final divider =
        Container(width: 1, height: 28, color: scheme.outlineVariant);
    return Container(
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        cell('Posts', posts, null),
        divider,
        cell(
            'Followers',
            followers,
            () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ConnectionsScreen(userId: widget.userId, initialIndex: 0)))),
        divider,
        cell(
            'Following',
            following,
            () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ConnectionsScreen(userId: widget.userId, initialIndex: 1)))),
        divider,
        cell('Friends', friends, null),
      ]),
    );
  }

  Widget _postsSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              for (final (i, label, icon) in const [
                (0, 'Posts', Icons.grid_view_rounded),
                (1, 'Media', Icons.photo_library_outlined),
                (2, 'Likes', Icons.favorite_border),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setTab(i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _tab == i ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon,
                              size: 16,
                              color:
                                  _tab == i ? Colors.white : scheme.outline),
                          const SizedBox(width: 6),
                          Text(label,
                              style: TextStyle(
                                  color: _tab == i
                                      ? Colors.white
                                      : scheme.outline,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Post>>(
          future: _currentFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            var posts = snap.data ?? const <Post>[];
            if (_tab == 1) {
              posts = posts.where((p) => p.media.isNotEmpty).toList();
            }
            if (posts.isEmpty) {
              final what = switch (_tab) {
                1 => 'No media yet.',
                2 => 'No liked posts yet.',
                _ => 'No posts yet.',
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                    child: Text(what,
                        style: TextStyle(color: scheme.outline))),
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
    );
  }
}


/// The signed-in user's own profile — okayspace-style profile card.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<User> _me = api.auth.me();

  Future<void> _reload() async {
    setState(() => _me = api.auth.me());
    await _me;
  }

  Future<void> _editProfile(User user) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EditProfileScreen(user: user),
    ));
    if (saved == true && mounted) _reload();
  }

  Future<void> _openSettings(User u) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SettingsScreen(user: u)));
    if (mounted) _reload();
  }

  int _stat(User u, List<String> keys) {
    final s = u.raw['stats'];
    if (s is Map) {
      for (final k in keys) {
        final v = s[k];
        if (v is num) return v.toInt();
      }
    }
    for (final k in keys) {
      final v = u.raw[k];
      if (v is num) return v.toInt();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: FutureBuilder<User>(
                future: _me,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return CenteredMessage(
                        message: messageFor(snapshot.error),
                        icon: Icons.error_outline);
                  }
                  final u = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      children: [
                        MaxWidth(child: _profileCard(u)),
                        const SizedBox(height: 12),
                        MaxWidth(child: _MyPostsSection(userId: u.userId)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          Text('Profile',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
          const Spacer(),
          FutureBuilder<User>(
            future: _me,
            builder: (c, s) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share',
              onPressed: s.data == null
                  ? null
                  : () {
                      final u = s.data!;
                      final handle = (u.username ?? u.userId);
                      final url = 'https://okayspace.ca/$handle';
                      Clipboard.setData(ClipboardData(text: url));
                      showInfo(context, 'Profile link copied: $url');
                    },
            ),
          ),
          FutureBuilder<User>(
            future: _me,
            builder: (c, s) => IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: s.data == null ? null : () => _openSettings(s.data!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(User u) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, darken(scheme.primary, 0.25)],
                  ),
                ),
              ),
              Positioned(
                top: 56,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: Avatar(url: u.picture, name: u.name, radius: 42),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: GestureDetector(
                  onTap: () => _editProfile(u),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black45,
                    child: Icon(Icons.photo_camera, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 52),
          Text(u.name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(u.handle, style: TextStyle(color: scheme.primary)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _levelPill(u),
          ),
          const SizedBox(height: 12),
          if (u.interests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in u.interests)
                    Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap),
                ],
              ),
            ),
          if (u.headline != null && u.headline!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(u.headline!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          _infoRow(u),
          if (u.bio != null && u.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(u.bio!, textAlign: TextAlign.center),
            ),
          ],
          const SizedBox(height: 8),
          _emailRow(u),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _statsRow(u),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _editProfile(u),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelPill(User u) {
    final scheme = Theme.of(context).colorScheme;
    final raw = u.raw['points_to_next'] ?? u.raw['pts_to_next'];
    final toNext = raw is num ? raw.toInt() : null;
    final progress = (toNext != null && (u.points + toNext) > 0)
        ? u.points / (u.points + toNext)
        : (u.points % 100) / 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department, color: scheme.primary, size: 18),
              const SizedBox(width: 6),
              Text('${u.points} points',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('Lv ${u.level}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(u.levelTitle,
                    style: TextStyle(color: scheme.outline)),
              ),
              Icon(Icons.chevron_right, color: scheme.outline, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          if (toNext != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('$toNext pts to Lv ${u.level + 1}',
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(User u) {
    final scheme = Theme.of(context).colorScheme;
    final birthday = '${u.raw['birthday'] ?? ''}';
    final items = <Widget>[
      if (u.location != null && u.location!.isNotEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.place_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 4),
          Text(u.location!),
        ]),
      if (birthday.isNotEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cake_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 4),
          Text(birthday.split('T').first),
        ]),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: items);
  }

  Widget _emailRow(User u) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(u.email,
              style: TextStyle(color: scheme.outline),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 11, color: scheme.outline),
            const SizedBox(width: 3),
            Text('Only you',
                style: TextStyle(color: scheme.outline, fontSize: 11)),
          ]),
        ),
      ],
    );
  }

  Widget _statsRow(User u) {
    final scheme = Theme.of(context).colorScheme;
    final posts = _stat(u, ['posts', 'post_count', 'posts_count']);
    final followers =
        _stat(u, ['followers', 'followers_count', 'follower_count']);
    final following = _stat(u, ['following', 'following_count']);
    final friends = _stat(u, ['friends', 'friends_count', 'friend_count']);
    Widget cell(String label, int value, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text(formatCount(value),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
              ]),
            ),
          ),
        );
    final divider = Container(width: 1, height: 28, color: scheme.outlineVariant);
    return Container(
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        cell('Posts', posts, null),
        divider,
        cell(
            'Followers',
            followers,
            () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ConnectionsScreen(userId: u.userId, initialIndex: 0)))),
        divider,
        cell(
            'Following',
            following,
            () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ConnectionsScreen(userId: u.userId, initialIndex: 1)))),
        divider,
        cell(
            'Friends',
            friends,
            () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FriendsScreen()))),
      ]),
    );
  }
}

/// The signed-in user's own posts, with Posts / Media / Likes tabs, rendered
/// inline so it scrolls with the profile card above it.
class _MyPostsSection extends StatefulWidget {
  const _MyPostsSection({required this.userId});

  final String userId;

  @override
  State<_MyPostsSection> createState() => _MyPostsSectionState();
}

class _MyPostsSectionState extends State<_MyPostsSection> {
  int _tab = 0;
  late Future<List<Post>> _posts = api.users.posts(widget.userId);
  Future<List<Post>>? _media;
  Future<List<Post>>? _likes;

  Future<List<Post>> _future() {
    switch (_tab) {
      case 1:
        return _media ??= api.users.posts(widget.userId);
      case 2:
        return _likes ??= api.users.likes(widget.userId);
      default:
        return _posts;
    }
  }

  void _reloadCurrent() {
    setState(() {
      switch (_tab) {
        case 1:
          _media = api.users.posts(widget.userId);
        case 2:
          _likes = api.users.likes(widget.userId);
        default:
          _posts = api.users.posts(widget.userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Segmented tab selector.
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              for (final (i, label, icon) in const [
                (0, 'Posts', Icons.grid_view_rounded),
                (1, 'Media', Icons.photo_library_outlined),
                (2, 'Likes', Icons.favorite_border),
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tab = i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _tab == i ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon,
                              size: 16,
                              color: _tab == i ? Colors.white : scheme.outline),
                          const SizedBox(width: 6),
                          Text(label,
                              style: TextStyle(
                                  color:
                                      _tab == i ? Colors.white : scheme.outline,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Post>>(
          future: _future(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Text(messageFor(snapshot.error),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.outline)),
                      const SizedBox(height: 8),
                      OutlinedButton(
                          onPressed: _reloadCurrent,
                          child: const Text('Retry')),
                    ],
                  ),
                ),
              );
            }
            final posts = snapshot.data ?? const [];
            final filtered = _tab == 1
                ? [for (final p in posts) if (p.media.isNotEmpty) p]
                : posts;
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                          _tab == 2
                              ? Icons.favorite_border
                              : _tab == 1
                                  ? Icons.photo_library_outlined
                                  : Icons.article_outlined,
                          size: 48,
                          color: scheme.outline),
                      const SizedBox(height: 10),
                      Text(
                          _tab == 2
                              ? 'No liked posts yet.'
                              : _tab == 1
                                  ? 'No media posts yet.'
                                  : 'No posts yet.',
                          style: TextStyle(color: scheme.outline)),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final p in filtered)
                  PostTile(post: p, card: true, onChanged: _reloadCurrent),
              ],
            );
          },
        ),
      ],
    );
  }
}
