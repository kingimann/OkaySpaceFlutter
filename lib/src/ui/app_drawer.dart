import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'app.dart';
import 'bookmarks_screen.dart';
import 'common.dart';
import 'communities_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'map_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';
import 'roadside_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'wallet_screen.dart';

/// Side menu opened from the feed header — styled after okayspace.ca's sidebar.
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

  Future<void> _openSettings() async {
    final u = await _me;
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SettingsScreen(user: u)));
  }

  Future<void> _signOut() async {
    await api.auth.logout();
    if (!mounted) return;
    // Replace everything with a fresh gate; it re-checks auth -> login.
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
            // Brand.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  const Text('OkaySpace',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('BETA',
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // User card.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FutureBuilder<User>(
                future: _me,
                builder: (context, snap) {
                  final u = snap.data;
                  return Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: u == null
                          ? null
                          : () {
                              Navigator.pop(context);
                              ProfileScreen.open(context, u.userId);
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Avatar(
                                url: u?.picture, name: u?.name ?? '?', radius: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u?.name ?? 'Loading…',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  if (u != null)
                                    Text(u.email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: scheme.outline,
                                            fontSize: 13)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: scheme.outline),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('YOUR SHORTCUTS',
                  style: TextStyle(
                      color: scheme.outline,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
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
                  _Shortcut(
                    icon: Icons.people_alt_rounded,
                    color: const Color(0xFF6366F1),
                    label: 'Friends',
                    onTap: () => _push(const FriendsScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.search_rounded,
                    color: const Color(0xFF14B8A6),
                    label: 'Search',
                    onTap: () => _push(const SearchScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.notifications_rounded,
                    color: const Color(0xFFF59E0B),
                    label: 'Notifications',
                    onTap: () => _push(const NotificationsScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.bookmark_rounded,
                    color: const Color(0xFFF97316),
                    label: 'Bookmarks',
                    onTap: () => _push(const BookmarksScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF22C55E),
                    label: 'Wallet',
                    onTap: () => _push(const WalletScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.car_repair_rounded,
                    color: const Color(0xFFEAB308),
                    label: 'Roadside',
                    onTap: () => _push(const RoadsideScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.support_agent_rounded,
                    color: const Color(0xFF0EA5E9),
                    label: 'Support',
                    onTap: () => _push(const SupportScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.settings_rounded,
                    color: const Color(0xFF8696A0),
                    label: 'Settings',
                    onTap: _openSettings,
                  ),
                  const Divider(height: 24, indent: 20, endIndent: 20),
                  _Shortcut(
                    icon: Icons.refresh_rounded,
                    color: scheme.primary,
                    label: 'Refresh / get latest update',
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
              padding: const EdgeInsets.all(16),
              child: Text('OkaySpace · v1.0',
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
            ),
          ],
        ),
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
