import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'ads_screen.dart';
import 'api_keys_screen.dart';
import 'app.dart';
import 'bookmarks_screen.dart';
import 'circles_screen.dart';
import 'common.dart';
import 'communities_screen.dart';
import 'connections_screen.dart';
import 'edit_profile_screen.dart';
import 'forms_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'guides_screen.dart';
import 'leaderboard_screen.dart';
import 'map_screen.dart';
import 'marketplace_screen.dart';
import 'more_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';
import 'videos_screen.dart';
import 'roadside_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'wallet_screen.dart';

/// Side menu opened from the feed header — styled after okayspace.ca's sidebar.
///
/// Organised into a profile card, quick actions, grouped navigation sections,
/// and inline appearance settings (theme + accent) that apply immediately.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late Future<User> _me = api.auth.me();

  /// Opens the signed-in user's OWN profile — the full owner view
  /// (MyProfileScreen: edit, customize, view-as-visitor), never the public
  /// visitor view of yourself.
  void _openMyProfile() {
    final nav = Navigator.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    nav.pop(); // close the drawer
    nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: kPrimaryRouteName),
      builder: (_) => MyProfileScreen(
        onSignedOut: () => rootNav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RootGate()),
          (route) => false,
        ),
      ),
    ));
  }

  void _push(Widget screen) {
    // Capture the navigator before popping: when the drawer is shown as a
    // modal (on pushed routes), the pop deactivates this context.
    final nav = Navigator.of(context);
    nav.pop();
    // Tagged primary so the destination's app bar shows the sidebar menu
    // (not a back button).
    nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: kPrimaryRouteName),
      builder: (_) => screen,
    ));
  }

  /// Pushes a screen that needs the loaded [User]; waits for it first.
  Future<void> _pushWithUser(Widget Function(User) builder) async {
    final u = await _me;
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: kPrimaryRouteName),
      builder: (_) => builder(u),
    ));
  }

  /// Builds a sidebar shortcut row for a destination id (see [kAllSidebarDests]).
  @override
  void initState() {
    super.initState();
    _loadWalletPending();
  }

  /// Incoming money requests awaiting the user, badged on the Wallet row.
  int _walletPending = 0;

  void _loadWalletPending() {
    api.wallet.moneyRequests().then((d) {
      var c = 0;
      if (d is Map && d['incoming'] is List) {
        c = (d['incoming'] as List).length;
      }
      if (mounted && c != _walletPending) {
        setState(() => _walletPending = c);
      }
    }).catchError((_) {});
  }

  Widget _shortcutFor(String id) {
    final d = sidebarDestById(id);
    return _Shortcut(
      icon: d.icon,
      color: d.color,
      label: d.label,
      badge: id == 'wallet' ? _walletPending : 0,
      onTap: () {
        switch (id) {
          case 'feed':
            // Close the drawer/modal, return to the shell, and select the feed
            // tab (re-tapping while already on it scrolls to top).
            final nav = Navigator.of(context);
            nav.pop();
            nav.popUntil((r) => r.isFirst);
            if (homeTabSignal.value == 'feed') feedScrollSignal.value++;
            homeTabSignal.select('feed');
          case 'reels':
            _push(const ReelsScreen());
          case 'videos':
            _push(const VideosScreen());
          case 'map':
            _push(const MapScreen());
          case 'guides':
            _push(const GuidesScreen());
          case 'marketplace':
            _push(const MarketplaceScreen());
          case 'communities':
            _push(const CommunitiesScreen());
          case 'groups':
            _push(const GroupsScreen());
          case 'profile':
            // Your own profile = the owner view (MyProfileScreen on the
            // home Profile tab), not the public visitor view.
            _openMyProfile();
          case 'friends':
            _push(const FriendsScreen());
          case 'connections':
            _pushWithUser((u) => ConnectionsScreen(userId: u.userId));
          case 'circles':
            _push(const CirclesScreen());
          case 'bookmarks':
            _push(const BookmarksScreen());
          case 'leaderboard':
            _push(const LeaderboardScreen());
          case 'notifications':
            _push(const NotificationsScreen());
          case 'wallet':
            _push(const WalletScreen());
          case 'search':
            _push(const SearchScreen());
          case 'roadside':
            _push(const RoadsideScreen());
          case 'forms':
            _push(const FormsScreen());
          case 'advertising':
            _push(const AdsScreen());
          case 'apikeys':
            _push(const ApiKeysScreen());
          case 'support':
            _push(const SupportScreen());
        }
      },
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await api.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand + quick settings gear.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Text('OkaySpace',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('BETA',
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () =>
                        _pushWithUser((u) => SettingsScreen(user: u)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _profileCard(scheme),
                  const SizedBox(height: 8),

                  // Customizable shortcut list (see Customize sidebar).
                  ValueListenableBuilder<List<String>>(
                    valueListenable: sidebarController,
                    builder: (context, ids, _) => Column(
                      children: [
                        for (final id in ids) _shortcutFor(id),
                      ],
                    ),
                  ),

                  const Divider(height: 24, indent: 20, endIndent: 20),
                  _Shortcut(
                    icon: Icons.apps_rounded,
                    color: const Color(0xFF6366F1),
                    label: 'More',
                    onTap: () => _push(const MoreScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.settings_rounded,
                    color: const Color(0xFF8696A0),
                    label: 'All settings',
                    onTap: () => _pushWithUser((u) => SettingsScreen(user: u)),
                  ),
                  _Shortcut(
                    icon: Icons.refresh_rounded,
                    color: scheme.primary,
                    label: 'Refresh',
                    onTap: () {
                      setState(() => _me = api.auth.me());
                      loadCurrentUserId();
                      showInfo(context, 'Refreshed');
                    },
                  ),
                  _Shortcut(
                    icon: Icons.logout_rounded,
                    color: const Color(0xFFEF4444),
                    label: 'Sign out',
                    labelColor: const Color(0xFFEF4444),
                    onTap: _signOut,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text('OkaySpace · v1.0.0',
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // --- Profile card -------------------------------------------------------

  Widget _profileCard(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: FutureBuilder<User>(
        future: _me,
        builder: (context, snap) {
          final u = snap.data;
          return Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: u == null ? null : _openMyProfile,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Avatar(
                            url: u?.picture, name: u?.name ?? '?', radius: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(u?.name ?? 'Loading…',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                  ),
                                  if (u?.verified ?? false) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified,
                                        size: 15, color: Color(0xFF3B82F6)),
                                  ],
                                ],
                              ),
                              Text(u?.handle ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Edit profile',
                          visualDensity: VisualDensity.compact,
                          onPressed: u == null
                              ? null
                              : () => _pushWithUser(
                                  (user) => EditProfileScreen(user: user)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A sidebar row: a colored squircle icon + label.
class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.badge = 0,
  });

  final IconData icon;
  final Color color;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final leading = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 22),
    );
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: badge > 0 ? Badge.count(count: badge, child: leading) : leading,
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: labelColor ?? Theme.of(context).colorScheme.onSurface)),
    );
  }
}
