import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../okayspace_api.dart';
import '../core/points_ledger.dart';
import 'activity_screen.dart';
import 'app_drawer.dart';
import 'bookmarks_screen.dart';
import 'business_screen.dart';
import 'circles_screen.dart';
import 'common.dart';
import 'badges_screen.dart';
import 'compose_screen.dart';
import 'connections_screen.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';
import 'hashtag_screen.dart';
import 'level_up.dart';
import 'linked_text.dart';
import 'money_guards.dart';
import 'wallet_screen.dart';
import 'leaderboard_screen.dart';
import 'levels_screen.dart';
import 'messages_screen.dart';
import 'post_tile.dart';
import 'profile_decor.dart';
import 'settings_screen.dart';

/// Shows a scannable QR code of a user's profile link in a bottom sheet.
void showProfileQr(BuildContext context,
    {required String name, required String handle}) {
  final url = 'https://okayspace.ca/$handle';
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('@$handle',
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                  data: url, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('Scan to view this profile',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy link'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
                showInfo(context, 'Profile link copied');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens a full-screen, zoomable view of a profile photo.
void showAvatarViewer(BuildContext context, String? url, String name) {
  if (url == null || url.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(name),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.person,
                  size: 120, color: Colors.white24)),
        ),
      ),
    ),
  ));
}

/// A profile bio that collapses long text behind a "Read more" toggle.
class _ExpandableBio extends StatefulWidget {
  const _ExpandableBio(this.text);
  final String text;

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final long = widget.text.length > 160;
    final toggle = GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_expanded ? 'Show less' : 'Read more',
            style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!long || _expanded)
          LinkedText(widget.text, textAlign: TextAlign.center)
        else
          Text(widget.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        if (long) toggle,
      ],
    );
  }
}

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
  Future<List<Post>>? _replies;
  Future<List<Post>>? _reposts;
  bool _following = false;
  // 0 Posts · 1 Media · 2 Likes · 3 Replies · 4 Reposts
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
      if (t == 3) _replies ??= api.users.replies(widget.userId);
      if (t == 4) _reposts ??= api.users.reposts(widget.userId);
      if (t == 2) _likes ??= api.users.likes(widget.userId);
    });
  }

  Future<List<Post>> get _currentFuture {
    switch (_tab) {
      case 2:
        return _likes!;
      case 3:
        return _replies!;
      case 4:
        return _reposts!;
      default:
        return _posts; // Posts and Media share the posts future
    }
  }

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
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Send money'),
              onTap: () => Navigator.pop(context, 'pay'),
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
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('Show QR code'),
              onTap: () => Navigator.pop(context, 'qr'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy profile link'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.forward_to_inbox_outlined),
              title: const Text('Share to a chat'),
              onTap: () => Navigator.pop(context, 'share'),
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
        case 'pay':
          if (mounted) await _payUser(u);
        case 'qr':
          if (mounted) _showQrFor(u);
        case 'copy':
          await Clipboard.setData(ClipboardData(
              text:
                  'https://okayspace.ca/u/${u.username ?? widget.userId}'));
          if (mounted) showInfo(context, 'Link copied');
        case 'share':
          await _shareProfileToChat(u);
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

  String _convName(ConversationView c) {
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  /// Shares this profile as a contact card into a conversation the user picks.
  Future<void> _shareProfileToChat(PublicUser u) async {
    final convs = await api.messaging
        .conversations()
        .catchError((_) => <ConversationView>[]);
    if (!mounted) return;
    final target = await showModalBottomSheet<ConversationView>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Share to',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in convs)
                    ListTile(
                      leading: Avatar(
                          url: c.avatar ?? c.otherUser?.picture,
                          name: _convName(c)),
                      title: Text(_convName(c),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await api.messaging
        .send(target.id, MessageCreate(type: 'contact', contactUserId: u.userId));
    if (mounted) showInfo(context, 'Shared');
  }

  void _showQrFor(PublicUser u) =>
      showProfileQr(context, name: u.name, handle: u.username ?? widget.userId);

  /// Sends money to this user via the full send flow — same screen as the
  /// profile Pay button, so balance/spending-limit checks and the payment
  /// confirmation all apply (the old inline dialog here bypassed them).
  Future<void> _payUser(PublicUser u) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => SendMoneyScreen(recipient: u)));

  /// Edit profile (own profile only): loads the full [User] then opens the
  /// editor, refreshing this screen on return.
  Future<void> _editProfileById(String userId) async {
    try {
      final me = await api.auth.me();
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => EditProfileScreen(user: me)));
      if (saved == true && mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _tip() async {
    final amountText = await promptText(context,
        title: 'Send a tip', hint: 'Amount', action: 'Send');
    if (amountText == null || !mounted) return;
    final amount = parseMoney(amountText);
    if (amount == null) {
      showInfo(context, 'Enter a valid amount.');
      return;
    }
    if (isSelf(widget.userId)) {
      showInfo(context, 'You can\'t tip yourself.');
      return;
    }
    final issue = amountIssue(amount, max: 500, what: 'tip');
    if (issue != null) {
      showInfo(context, issue);
      return;
    }
    if (!await confirmLargeAmount(context, amount, threshold: 100) ||
        !mounted) {
      return;
    }
    final dupKey = 'tip:${widget.userId}:$amount';
    if (isRecentDuplicate(dupKey)) {
      final repeat = await confirmDuplicate(
          context, 'tipped \$${amount.toStringAsFixed(2)}');
      if (!repeat || !mounted) return;
    }
    try {
      await api.users.tip(widget.userId, amount);
      markMoneyAction(dupKey);
      if (mounted) showInfo(context, 'Tipped \$${amount.toStringAsFixed(2)} 🎉');
    } catch (e) {
      if (mounted) showError(context, e);
    }
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

  /// Online presence, "follows you" and subscriber chips for a public profile.
  Widget _publicMeta(PublicUser u) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(IconData icon, String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    final chips = <Widget>[
      chip(Icons.circle, u.online ? 'Online' : 'Offline',
          u.online ? const Color(0xFF22C55E) : scheme.outline),
      if (u.isFollowedBy) chip(Icons.how_to_reg, 'Follows you', scheme.primary),
      if (u.subscriberCount > 0)
        chip(Icons.workspace_premium_outlined,
            '${u.subscriberCount} subs', const Color(0xFFEAB308)),
    ];
    return Wrap(
        alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: chips);
  }

  /// The user's earned badges (UserBadges component, capped at 4).
  Widget _publicBadges(PublicUser u) {
    final badges = u.badges.where((b) => (b.label ?? '').isNotEmpty).take(4);
    if (badges.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final b in badges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      (b.icon != null &&
                              b.icon!.isNotEmpty &&
                              !b.icon!.startsWith('http'))
                          ? b.icon!
                          : '🏅',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(b.label!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Profile card mirroring My Profile: banner, avatar, name, level pill,
  /// info, stat cards and Follow/Message actions.
  /// Interests for a public profile (typed field is absent; read from raw).
  List<String> _publicInterests(PublicUser u) {
    final v = u.raw['interests'];
    return v is List
        ? v.map((e) => '$e').where((s) => s.isNotEmpty).take(12).toList()
        : const [];
  }

  /// Parses a hex accent colour from a public profile, falling back to primary.
  Color _publicAccent(PublicUser u) {
    final c = '${u.raw['accent_color'] ?? ''}'.replaceAll('#', '').trim();
    final v = int.tryParse(c.length == 6 ? 'FF$c' : c, radix: 16);
    return v != null ? Color(v) : Theme.of(context).colorScheme.primary;
  }

  Widget _profileCard(PublicUser u) {
    final scheme = Theme.of(context).colorScheme;
    final levelTitle = '${u.raw['level_title'] ?? ''}';
    final location = '${u.raw['location'] ?? ''}';
    final cover = '${u.raw['cover_photo'] ?? ''}';
    final accent = _publicAccent(u);
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
              GestureDetector(
                onTap: cover.isEmpty
                    ? null
                    : () => showAvatarViewer(context, cover, u.name),
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    image: cover.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(cover), fit: BoxFit.cover)
                        : null,
                    gradient: cover.isNotEmpty
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [accent, darken(accent, 0.25)],
                          ),
                  ),
                ),
              ),
              Positioned(
                top: 56,
                child: GestureDetector(
                  onTap: () => showAvatarViewer(context, u.picture, u.name),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.surfaceContainerLow,
                      border: Border.all(color: accent, width: 2),
                    ),
                    child: Avatar(url: u.picture, name: u.name, radius: 42),
                  ),
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
          const SizedBox(height: 6),
          _publicMeta(u),
          _publicBadges(u),
          const SizedBox(height: 12),
          if (u.points > 0 || u.level > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const LeaderboardScreen())),
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
          if (_publicInterests(u).isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in _publicInterests(u))
                    Chip(
                        label: Text(t),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap),
                ],
              ),
            ),
          ],
          if (u.bio != null && u.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ExpandableBio(u.bio!),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _statsRow(u),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: u.userId == currentUserId
                // Your own profile: owner actions, not Follow/Message/Pay.
                ? Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _editProfileById(u.userId),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit profile'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => showProfileDecorSheet(context),
                          icon: const Icon(Icons.palette_outlined, size: 18),
                          label: const Text('Customize'),
                        ),
                      ),
                    ],
                  )
                : Row(
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF008CFF),
                              foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      SendMoneyScreen(recipient: u))),
                          icon: const Icon(Icons.attach_money, size: 18),
                          label: const Text('Pay'),
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, label, icon) in const [
                  (0, 'Posts', Icons.grid_view_rounded),
                  (1, 'Media', Icons.photo_library_outlined),
                  (2, 'Likes', Icons.favorite_border),
                  (3, 'Replies', Icons.reply_outlined),
                  (4, 'Reposts', Icons.repeat),
                ])
                  GestureDetector(
                    onTap: () => _setTab(i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                          vertical: 9, horizontal: 14),
                      decoration: BoxDecoration(
                        color: _tab == i ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
              ],
            ),
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
                3 => 'No replies yet.',
                4 => 'No reposts yet.',
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
  late Future<User> _me = _load();
  late Future<List<Map<String, dynamic>>> _leaderboard =
      api.users.leaderboard().catchError((_) => <Map<String, dynamic>>[]);
  // Follower/following/friend counts — /auth/me omits them, so they come from
  // the public profile's `stats` object.
  Map<String, dynamic> _stats = const {};
  // Leaderboard places gained (+) or lost (-) since this device last looked.
  int? _rankDelta;

  /// Loads the signed-in user and (separately) the stats the /auth/me payload
  /// doesn't include.
  Future<User> _load() async {
    final u = await api.auth.me();
    api.users.publicProfile(u.userId).then((p) {
      final s = p.raw['stats'];
      if (mounted && s is Map) {
        setState(() => _stats = Map<String, dynamic>.from(s));
      }
    }).catchError((_) {});
    // Celebrate when the backend level has gone up since we last saw it.
    final oldLevel = pointsLedger.checkLevelUp(u.level);
    if (oldLevel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showLevelUpCelebration(context,
              oldLevel: oldLevel, newLevel: u.level, user: u);
        }
      });
    }
    // Celebrate a freshly-reached streak milestone.
    final milestone = pointsLedger.takePendingStreakMilestone();
    if (milestone != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showInfo(context, '🔥 $milestone-day streak! Bonus points earned');
        }
      });
    }
    // Note when a streak freeze saved the day.
    if (pointsLedger.takePendingFreezeUsed()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showInfo(context, '❄️ Streak freeze used — your streak is safe!');
        }
      });
    }
    // Cheer when today's points goal is reached.
    if (pointsLedger.takePendingGoalReached()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showInfo(context, '🎯 Daily goal reached — nice work!');
      });
    }
    // Note how the leaderboard rank has moved since this device last looked.
    _leaderboard.then((lb) {
      final rank = _rankIn(lb, u.userId);
      if (rank == null) return;
      final prev = pointsLedger.checkRankChange(rank);
      if (prev != null && prev != rank && mounted) {
        setState(() => _rankDelta = prev - rank); // >0 = moved up
      }
    }).catchError((_) {});
    return u;
  }

  Future<void> _reload() async {
    setState(() {
      _me = _load();
      _leaderboard =
          api.users.leaderboard().catchError((_) => <Map<String, dynamic>>[]);
    });
    await _me;
  }

  /// The user's 1-based rank within an already-loaded leaderboard, or null.
  int? _rankIn(List<Map<String, dynamic>> lb, String userId) {
    for (var i = 0; i < lb.length; i++) {
      final e = lb[i];
      final id = '${e['user_id'] ?? e['id'] ?? e['userId'] ?? ''}';
      if (id == userId) {
        final r = e['rank'];
        return r is num ? r.toInt() : i + 1;
      }
    }
    return null;
  }

  /// Finds the user's 1-based rank on the points leaderboard, or null.
  Future<int?> _rankFor(String userId) async =>
      _rankIn(await _leaderboard, userId);

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

  /// A compact privacy summary card linking to Settings (§4 privacy card).
  Widget _privacyCard(User u) {
    final scheme = Theme.of(context).colorScheme;
    final private = u.isPrivate;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSettings(u),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(private ? Icons.lock_outline : Icons.public,
                  color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(private ? 'Private account' : 'Public account',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        private
                            ? 'Only approved followers can see your posts'
                            : 'Anyone can see your posts and profile',
                        style: TextStyle(color: scheme.outline, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the post composer from the profile (§4 PostComposer).
  Future<void> _compose() async {
    final posted = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ComposeScreen()));
    if (posted == true && mounted) _reload();
  }

  /// Shares the user's own profile as a contact card into a chosen chat.
  Future<void> _shareSelfToChat(User u) async {
    final conv = await pickConversation(context);
    if (conv == null || !mounted) return;
    try {
      await api.messaging.send(
          conv.id, MessageCreate(type: 'contact', contactUserId: u.userId));
      if (mounted) showInfo(context, 'Shared');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  int _stat(User u, List<String> keys) {
    // Prefer the stats fetched from the public profile (/auth/me omits them).
    for (final k in keys) {
      final v = _stats[k];
      if (v is num) return v.toInt();
    }
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
      // Lift the compose button above the floating nav pill, and let it ride
      // the nav-bar hide-on-scroll animation instead of sitting behind it.
      floatingActionButton: ValueListenableBuilder<double>(
        valueListenable: barsT,
        builder: (context, t, child) => Padding(
          padding: EdgeInsets.only(bottom: 72 * t),
          child: child,
        ),
        child: FloatingActionButton(
          tooltip: 'New post',
          onPressed: _compose,
          child: const Icon(Icons.edit_outlined),
        ),
      ),
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
                        AnimatedBuilder(
                          animation: profileDecor,
                          builder: (_, __) => MaxWidth(child: _profileCard(u)),
                        ),
                        const SizedBox(height: 12),
                        MaxWidth(child: _privacyCard(u)),
                        const SizedBox(height: 12),
                        MaxWidth(child: _quickLinks()),
                        if (_completeness(u).$1 < 1.0) ...[
                          const SizedBox(height: 12),
                          MaxWidth(child: _completenessCard(u)),
                        ],
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

  /// Earned badges shown on the profile, parsed from the raw `badges` payload
  /// (list of strings or {name/label, icon/emoji} maps).
  Widget _achievementBadges(User u) {
    final raw = u.raw['badges'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    String labelOf(dynamic b) {
      if (b is Map) return '${b['label'] ?? b['name'] ?? b['title'] ?? ''}';
      return '$b';
    }

    String? emojiOf(dynamic b) {
      if (b is Map) {
        final e = b['emoji'] ?? b['icon'];
        if (e is String && e.isNotEmpty && !e.startsWith('http')) return e;
      }
      return null;
    }

    final badges = [
      for (final b in raw)
        if (labelOf(b).isNotEmpty) b
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final b in badges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emojiOf(b) ?? '🏅', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(labelOf(b),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Quick-access tiles to the user's saved posts, the leaderboard and
  /// close-friends circles.
  Widget _quickLinks() {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(IconData icon, String label, Widget screen) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => screen)),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(height: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        tile(Icons.bookmark_outline, 'Saved', const BookmarksScreen()),
        tile(Icons.bolt_outlined, 'Activity', const ActivityScreen()),
        tile(Icons.leaderboard_outlined, 'Leaderboard',
            const LeaderboardScreen()),
        tile(Icons.group_outlined, 'Circles', const CirclesScreen()),
      ],
    );
  }

  /// The profile accent: a locally-chosen theme wins, then the server-side
  /// hex accent, then the app theme primary.
  Color _accent(User u) {
    if (profileDecor.themeId != 'default') return profileDecor.theme.accent;
    final c = u.accentColor;
    if (c != null && c.isNotEmpty) {
      final hex = c.replaceAll('#', '').trim();
      final v = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      if (v != null) return Color(v);
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// The user's free-text status (e.g. "🟢 Available"), shown under the handle.
  Widget _statusLine(User u) {
    final status = '${u.raw['status'] ?? ''}'.trim();
    if (status.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(status, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  /// Tappable social-link icons parsed from the raw `socials`/`links` payload
  /// (map of platform→handle-or-url), mirroring the web app's socials lib.
  Widget _socialLinks(User u) {
    final raw = u.raw['socials'] ?? u.raw['links'] ?? u.raw['social_links'];
    if (raw is! Map || raw.isEmpty) return const SizedBox.shrink();
    const platforms = <String, (IconData, String)>{
      'website': (Icons.language, ''),
      'twitter': (Icons.alternate_email, 'https://x.com/'),
      'x': (Icons.alternate_email, 'https://x.com/'),
      'instagram': (Icons.camera_alt_outlined, 'https://instagram.com/'),
      'tiktok': (Icons.music_note, 'https://tiktok.com/@'),
      'youtube': (Icons.play_circle_outline, 'https://youtube.com/@'),
      'github': (Icons.code, 'https://github.com/'),
      'linkedin': (Icons.business_center_outlined, 'https://linkedin.com/in/'),
      'facebook': (Icons.facebook, 'https://facebook.com/'),
      'twitch': (Icons.videogame_asset_outlined, 'https://twitch.tv/'),
    };
    String urlFor(String key, String value) {
      if (value.startsWith('http')) return value;
      final p = platforms[key.toLowerCase()];
      final base = p?.$2 ?? '';
      return base.isEmpty ? value : '$base${value.replaceFirst('@', '')}';
    }

    final entries = <(IconData, String)>[];
    raw.forEach((k, v) {
      final key = '$k'.toLowerCase();
      final value = '$v'.trim();
      if (value.isEmpty) return;
      final p = platforms[key];
      entries.add(((p?.$1 ?? Icons.link), urlFor(key, value)));
    });
    if (entries.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, url) in entries)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                showInfo(context, 'Link copied: $url');
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  /// A small row of verification chips + "member since" for the profile card.
  Widget _verificationBadges(User u) {
    final scheme = Theme.of(context).colorScheme;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final d = u.createdAt.toLocal();
    Widget chip(IconData icon, String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        if (u.isPrivate)
          chip(Icons.lock_outline, 'Private', scheme.outline),
        if (u.emailVerified)
          chip(Icons.mark_email_read_outlined, 'Email', scheme.primary),
        if (u.phoneVerified)
          chip(Icons.phone_android, 'Phone', const Color(0xFF22C55E)),
        if (u.idVerified)
          chip(Icons.badge_outlined, 'ID', const Color(0xFF6366F1)),
        chip(Icons.cake_outlined, 'Since ${months[d.month - 1]} ${d.year}',
            scheme.outline),
        FutureBuilder<int?>(
          future: _rankFor(u.userId),
          builder: (context, snap) {
            if (snap.data == null) return const SizedBox.shrink();
            final d = _rankDelta;
            final move = (d == null || d == 0)
                ? ''
                : (d > 0 ? '  ▲$d' : '  ▼${-d}');
            return chip(Icons.leaderboard_outlined,
                'Rank #${snap.data}$move', const Color(0xFFEAB308));
          },
        ),
      ],
    );
  }

  /// Returns (fraction complete, list of missing field labels).
  (double, List<String>) _completeness(User u) {
    final checks = <String, bool>{
      'Profile photo': u.picture != null && u.picture!.isNotEmpty,
      'Cover photo': u.coverPhoto != null && u.coverPhoto!.isNotEmpty,
      'Bio': u.bio != null && u.bio!.isNotEmpty,
      'Headline': u.headline != null && u.headline!.isNotEmpty,
      'Location': u.location != null && u.location!.isNotEmpty,
      'Interests': u.interests.isNotEmpty,
    };
    final done = checks.values.where((v) => v).length;
    final missing = [
      for (final e in checks.entries)
        if (!e.value) e.key
    ];
    return (done / checks.length, missing);
  }

  Widget _completenessCard(User u) {
    final scheme = Theme.of(context).colorScheme;
    final (frac, missing) = _completeness(u);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_circle_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              const Text('Complete your profile',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              Text('${(frac * 100).round()}%',
                  style: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in missing)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(m),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editProfile(u),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQr(User u) =>
      showProfileQr(context, name: u.name, handle: u.username ?? u.userId);

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
            builder: (c, s) => PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Profile options',
              onSelected: (v) {
                final u = s.data;
                switch (v) {
                  case 'customize':
                    showProfileDecorSheet(context);
                  case 'qr':
                    if (u != null) _showQr(u);
                  case 'share':
                    if (u != null) {
                      final handle = u.username ?? u.userId;
                      final url = 'https://okayspace.ca/$handle';
                      Clipboard.setData(ClipboardData(text: url));
                      showInfo(context, 'Profile link copied: $url');
                    }
                  case 'sharechat':
                    if (u != null) _shareSelfToChat(u);
                  case 'copyhandle':
                    if (u != null) {
                      Clipboard.setData(
                          ClipboardData(text: '@${u.username ?? u.userId}'));
                      showInfo(context, 'Username copied');
                    }
                  case 'people':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FriendsScreen()));
                  case 'business':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const BusinessScreen()));
                  case 'levels':
                    if (u != null) {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LevelsScreen(user: u)));
                    }
                  case 'badges':
                    if (u != null) {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              BadgesScreen(user: u, stats: _stats)));
                    }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'levels',
                    child: ListTile(
                        leading: Icon(Icons.military_tech_outlined),
                        title: Text('Points & levels'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'badges',
                    child: ListTile(
                        leading: Icon(Icons.emoji_events_outlined),
                        title: Text('Badges'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'customize',
                    child: ListTile(
                        leading: Icon(Icons.palette_outlined),
                        title: Text('Customize'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'qr',
                    child: ListTile(
                        leading: Icon(Icons.qr_code),
                        title: Text('My QR code'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                        leading: Icon(Icons.ios_share),
                        title: Text('Share profile'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'sharechat',
                    child: ListTile(
                        leading: Icon(Icons.forward_to_inbox_outlined),
                        title: Text('Share to a chat'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'copyhandle',
                    child: ListTile(
                        leading: Icon(Icons.alternate_email),
                        title: Text('Copy username'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'people',
                    child: ListTile(
                        leading: Icon(Icons.people_outline),
                        title: Text('Find friends'),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'business',
                    child: ListTile(
                        leading: Icon(Icons.storefront_outlined),
                        title: Text('My business'),
                        contentPadding: EdgeInsets.zero)),
              ],
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
              SizedBox(
                height: 100,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        image: (!profileDecor.useBackground &&
                                u.coverPhoto != null &&
                                u.coverPhoto!.isNotEmpty)
                            ? DecorationImage(
                                image: NetworkImage(u.coverPhoto!),
                                fit: BoxFit.cover)
                            : null,
                        gradient: profileDecor.useBackground
                            ? profileDecor.background.gradient
                            : (u.coverPhoto != null &&
                                    u.coverPhoto!.isNotEmpty)
                                ? null
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _accent(u),
                                      darken(_accent(u), 0.25)
                                    ],
                                  ),
                      ),
                    ),
                    // Decorative pattern overlay (only on a gradient bg).
                    if (profileDecor.useBackground &&
                        profileDecor.patternId != 'none')
                      CustomPaint(
                        painter:
                            ProfilePatternPainter(profileDecor.patternId),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 56,
                child: GestureDetector(
                  onTap: () => showAvatarViewer(context, u.picture, u.name),
                  child: framedAvatar(
                    frame: profileDecor.frame,
                    surface: scheme.surfaceContainerLow,
                    shape: profileDecor.avatarShapeId,
                    child: Avatar(url: u.picture, name: u.name, radius: 42),
                  ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: profileNameText(
                    u.name,
                    Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    accent: _accent(u),
                    align: TextAlign.center),
              ),
              if (u.verified) ...[
                const SizedBox(width: 6),
                Icon(Icons.verified, color: scheme.primary, size: 20),
              ],
            ],
          ),
          Text(u.handle, style: TextStyle(color: scheme.primary)),
          _statusLine(u),
          const SizedBox(height: 6),
          _verificationBadges(u),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _levelPill(u),
          ),
          _achievementBadges(u),
          _socialLinks(u),
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
                    ActionChip(
                        label: Text('#$t'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => HashtagScreen.open(context, t)),
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
              child: _ExpandableBio(u.bio!),
            ),
          ],
          const SizedBox(height: 8),
          _emailRow(u),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _statsRow(u),
          ),
          if (_stat(u, ['profile_views', 'views', 'view_count']) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_outlined,
                      size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                      '${formatCount(_stat(u, ['profile_views', 'views', 'view_count']))} profile views',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                          fontSize: 12)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editProfile(u),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ProfileScreen.open(context, u.userId),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('View as visitor'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => LevelsScreen(user: u))),
      child: Container(
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
      ),
    );
  }

  Widget _infoRow(User u) {
    final scheme = Theme.of(context).colorScheme;
    final birthday = '${u.raw['birthday'] ?? ''}';
    final pronouns = '${u.raw['pronouns'] ?? ''}'.trim();
    final items = <Widget>[
      if (u.location != null && u.location!.isNotEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.place_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 4),
          Text(u.location!),
        ]),
      if (pronouns.isNotEmpty)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.badge_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 4),
          Text(pronouns),
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
  Future<List<Post>>? _replies;
  Future<List<Post>>? _reposts;

  Future<List<Post>> _future() {
    switch (_tab) {
      case 1:
        return _media ??= api.users.posts(widget.userId);
      case 2:
        return _likes ??= api.users.likes(widget.userId);
      case 3:
        return _replies ??= api.users.replies(widget.userId);
      case 4:
        return _reposts ??= api.users.reposts(widget.userId);
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
        case 3:
          _replies = api.users.replies(widget.userId);
        case 4:
          _reposts = api.users.reposts(widget.userId);
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
        // Segmented tab selector (scrolls horizontally to fit all tabs).
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, label, icon) in const [
                  (0, 'Posts', Icons.grid_view_rounded),
                  (1, 'Media', Icons.photo_library_outlined),
                  (2, 'Likes', Icons.favorite_border),
                  (3, 'Replies', Icons.reply_outlined),
                  (4, 'Reposts', Icons.repeat),
                ])
                  GestureDetector(
                    onTap: () => setState(() => _tab = i),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                          vertical: 9, horizontal: 14),
                      decoration: BoxDecoration(
                        color: _tab == i ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
              ],
            ),
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
              final (icon, label) = switch (_tab) {
                1 => (Icons.photo_library_outlined, 'No media posts yet.'),
                2 => (Icons.favorite_border, 'No liked posts yet.'),
                3 => (Icons.reply_outlined, 'No replies yet.'),
                4 => (Icons.repeat, 'No reposts yet.'),
                _ => (Icons.article_outlined, 'No posts yet.'),
              };
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Column(
                    children: [
                      Icon(icon, size: 48, color: scheme.outline),
                      const SizedBox(height: 10),
                      Text(label, style: TextStyle(color: scheme.outline)),
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
