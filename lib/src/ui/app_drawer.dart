import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'ads_screen.dart';
import 'api_keys_screen.dart';
import 'app.dart';
import 'common.dart';
import 'communities_screen.dart';
import 'customize_nav_screen.dart';
import 'edit_profile_screen.dart';
import 'forms_screen.dart';
import 'groups_screen.dart';
import 'guides_screen.dart';
import 'map_screen.dart';
import 'marketplace_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';
import 'roadside_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';

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
                    icon: Icons.collections_bookmark_rounded,
                    color: const Color(0xFF14B8A6),
                    label: 'Places & Guides',
                    onTap: () => _push(const GuidesScreen()),
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

                  _sectionHeader('SERVICES'),
                  _Shortcut(
                    icon: Icons.car_repair_rounded,
                    color: const Color(0xFFF43F5E),
                    label: 'Roadside assistance',
                    onTap: () => _push(const RoadsideScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.assignment_rounded,
                    color: const Color(0xFF8B5CF6),
                    label: 'Forms',
                    onTap: () => _push(const FormsScreen()),
                  ),
                  _Shortcut(
                    icon: Icons.campaign_rounded,
                    color: const Color(0xFFF97316),
                    label: 'Advertising',
                    onTap: () => _push(const AdsScreen()),
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

                  const Divider(height: 24, indent: 20, endIndent: 20),
                  _Shortcut(
                    icon: Icons.dashboard_customize_outlined,
                    color: const Color(0xFF06B6D4),
                    label: 'Customize navigation',
                    onTap: () => _push(const CustomizeNavScreen()),
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
                  ],
                ),
              ),
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
