import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'api_keys_screen.dart';
import 'app.dart';
import 'bookmarks_screen.dart';
import 'common.dart';
import 'communities_screen.dart';
import 'compose_screen.dart';
import 'connections_screen.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'map_screen.dart';
import 'marketplace_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';
import 'roadside_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'story_composer.dart';
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

  void _push(Widget screen) {
    Navigator.pop(context);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Pushes a screen that needs the loaded [User]; waits for it first.
  Future<void> _pushWithUser(Widget Function(User) builder) async {
    final u = await _me;
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder(u)));
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
                  const SizedBox(height: 12),
                  _quickActions(scheme),
                  const SizedBox(height: 8),

                  _sectionHeader('DISCOVER'),
                  _Shortcut(
                    icon: Icons.home_rounded,
                    color: const Color(0xFF3B82F6),
                    label: 'Feed',
                    onTap: () => Navigator.pop(context),
                  ),
                  _Shortcut(
                    icon: Icons.videocam_rounded,
                    color: const Color(0xFFEC4899),
                    label: 'Reels',
                    onTap: () => _push(const ReelsScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.map_rounded,
                    color: const Color(0xFF10B981),
                    label: 'Map',
                    onTap: () => _push(const MapScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.storefront_rounded,
                    color: const Color(0xFFF97316),
                    label: 'Marketplace',
                    onTap: () => _push(const MarketplaceScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.tag_rounded,
                    color: const Color(0xFF06B6D4),
                    label: 'Communities',
                    onTap: () => _push(const CommunitiesScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.groups_rounded,
                    color: const Color(0xFFA855F7),
                    label: 'Groups',
                    onTap: () => _push(const GroupsScreen()),
                  ),

                  _sectionHeader('YOU'),
                  _Shortcut(
                    icon: Icons.person_rounded,
                    color: const Color(0xFF14B8A6),
                    label: 'My profile',
                    onTap: () => _pushWithUser(
                        (u) => ProfileScreen(userId: u.userId)),
                  ),
                  _Shortcut(
                    icon: Icons.people_alt_rounded,
                    color: const Color(0xFF6366F1),
                    label: 'Friends',
                    onTap: () => _push(const FriendsScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.group_add_rounded,
                    color: const Color(0xFF8B5CF6),
                    label: 'Followers & following',
                    onTap: () => _pushWithUser(
                        (u) => ConnectionsScreen(userId: u.userId)),
                  ),
                  _Shortcut(
                    icon: Icons.bookmark_rounded,
                    color: const Color(0xFFF59E0B),
                    label: 'Bookmarks',
                    onTap: () => _push(const BookmarksScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.notifications_rounded,
                    color: const Color(0xFFEAB308),
                    label: 'Notifications',
                    onTap: () => _push(const NotificationsScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF22C55E),
                    label: 'Wallet',
                    onTap: () => _push(const WalletScreen()),
                  ),

                  _sectionHeader('SERVICES'),
                  _Shortcut(
                    icon: Icons.car_repair_rounded,
                    color: const Color(0xFFF43F5E),
                    label: 'Roadside assistance',
                    onTap: () => _push(const RoadsideScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.vpn_key_rounded,
                    color: const Color(0xFF0EA5E9),
                    label: 'Developer API keys',
                    onTap: () => _push(const ApiKeysScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.support_agent_rounded,
                    color: const Color(0xFF38BDF8),
                    label: 'Help & support',
                    onTap: () => _push(const SupportScreen()),
                  ),

                  _sectionHeader('APPEARANCE'),
                  _themePicker(scheme),
                  _accentPicker(scheme),

                  const Divider(height: 24, indent: 20, endIndent: 20),
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
              onTap: u == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      ProfileScreen.open(context, u.userId);
                    },
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
                    if (u != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _stat(
                              scheme,
                              Icons.military_tech_rounded,
                              const Color(0xFFF59E0B),
                              u.levelTitle.isNotEmpty
                                  ? u.levelTitle
                                  : 'Level ${u.level}',
                              '${formatCount(u.points)} pts'),
                          const SizedBox(width: 10),
                          _stat(
                              scheme,
                              Icons.account_balance_wallet_rounded,
                              const Color(0xFF22C55E),
                              'Wallet',
                              '${u.currency} ${u.walletBalance.toStringAsFixed(2)}'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stat(ColorScheme scheme, IconData icon, Color color, String title,
      String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.outline, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Quick actions ------------------------------------------------------

  Widget _quickActions(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _quickAction(scheme, Icons.edit_rounded, 'Post',
              () => _push(const ComposeScreen())),
          const SizedBox(width: 8),
          _quickAction(scheme, Icons.add_a_photo_rounded, 'Story', () {
            Navigator.pop(context);
            StoryComposer.start(context);
          }),
          const SizedBox(width: 8),
          _quickAction(scheme, Icons.search_rounded, 'Search',
              () => _push(const SearchScreen())),
        ],
      ),
    );
  }

  Widget _quickAction(
      ColorScheme scheme, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, color: scheme.primary, size: 22),
                const SizedBox(height: 4),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Inline appearance settings ----------------------------------------

  Widget _themePicker(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeController,
        builder: (context, mode, _) {
          return SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto, size: 18),
                  label: Text('Auto')),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode, size: 18),
                  label: Text('Light')),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode, size: 18),
                  label: Text('Dark')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => themeController.set(s.first),
          );
        },
      ),
    );
  }

  Widget _accentPicker(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
      child: ValueListenableBuilder<Color>(
        valueListenable: accentController,
        builder: (context, current, _) {
          return SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kAccents.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final a = kAccents[i];
                final selected =
                    a.color.toARGB32() == current.toARGB32();
                return GestureDetector(
                  onTap: () => accentController.set(a.color),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: a.color,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: scheme.onSurface, width: 3)
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(title,
          style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6)),
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
  });

  final IconData icon;
  final Color color;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: labelColor ?? Theme.of(context).colorScheme.onSurface)),
    );
  }
}
