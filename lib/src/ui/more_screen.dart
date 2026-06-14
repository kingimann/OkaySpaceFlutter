import 'package:flutter/material.dart';

import 'ads_screen.dart';
import 'api_keys_screen.dart';
import 'bookmarks_screen.dart';
import 'calendar_screen.dart';
import 'camera_screen.dart';
import 'circles_screen.dart';
import 'common.dart';
import 'communities_screen.dart';
import 'connections_screen.dart';
import 'forms_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'guides_screen.dart';
import 'leaderboard_screen.dart';
import 'map_screen.dart';
import 'marketplace_screen.dart';
import 'notes_screen.dart';
import 'notifications_screen.dart';
import 'reels_screen.dart';
import 'roadside_screen.dart';
import 'search_screen.dart';
import 'support_screen.dart';
import 'videos_screen.dart';
import 'wallet_screen.dart';

class _Item {
  const _Item(this.label, this.icon, this.color, this.builder);
  final String label;
  final IconData icon;
  final Color color;
  final Widget Function() builder;
}

class _Section {
  const _Section(this.title, this.items);
  final String title;
  final List<_Item> items;
}

/// A hub that lists every feature so anything not pinned to the bottom bar is
/// still one tap away. Opened from the drawer, next to Settings.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  List<_Section> _sections() => [
        _Section('Personal', [
          _Item('Notes', Icons.sticky_note_2_outlined, const Color(0xFFF59E0B),
              () => const NotesScreen()),
          _Item('Calendar', Icons.calendar_today_outlined,
              const Color(0xFF14B8A6), () => const CalendarScreen()),
          _Item('Camera', Icons.photo_camera_outlined, const Color(0xFF6366F1),
              () => const CameraScreen()),
          _Item('Bookmarks', Icons.bookmark_outline, const Color(0xFFEAB308),
              () => const BookmarksScreen()),
        ]),
        _Section('Explore', [
          _Item('Map', Icons.map_outlined, const Color(0xFF10B981),
              () => const MapScreen()),
          _Item('Marketplace', Icons.storefront_outlined,
              const Color(0xFFF97316), () => const MarketplaceScreen()),
          _Item('Communities', Icons.tag, const Color(0xFF06B6D4),
              () => const CommunitiesScreen()),
          _Item('Groups', Icons.groups_outlined, const Color(0xFFA855F7),
              () => const GroupsScreen()),
          _Item('Guides', Icons.menu_book_outlined, const Color(0xFF8B5CF6),
              () => const GuidesScreen()),
          _Item('Videos', Icons.smart_display_outlined,
              const Color(0xFFEF4444), () => const VideosScreen()),
          _Item('Reels', Icons.play_circle_outline, const Color(0xFFEC4899),
              () => const ReelsScreen()),
          _Item('Search', Icons.search, const Color(0xFF3B82F6),
              () => const SearchScreen()),
        ]),
        _Section('You', [
          _Item('Wallet', Icons.account_balance_wallet_outlined,
              const Color(0xFF22C55E), () => const WalletScreen()),
          _Item('Friends', Icons.people_outline, const Color(0xFF0EA5E9),
              () => const FriendsScreen()),
          _Item('Connections', Icons.hub_outlined, const Color(0xFF14B8A6),
              () => ConnectionsScreen(userId: currentUserId ?? '')),
          _Item('Notifications', Icons.notifications_outlined,
              const Color(0xFFF43F5E), () => const NotificationsScreen()),
          _Item('Leaderboard', Icons.leaderboard_outlined,
              const Color(0xFFFBBF24), () => const LeaderboardScreen()),
          _Item('Circles', Icons.group_work_outlined, const Color(0xFF8B5CF6),
              () => const CirclesScreen()),
        ]),
        _Section('Tools', [
          _Item('Roadside', Icons.car_crash_outlined, const Color(0xFFEF4444),
              () => const RoadsideScreen()),
          _Item('Forms', Icons.description_outlined, const Color(0xFF3B82F6),
              () => const FormsScreen()),
          _Item('Advertising', Icons.campaign_outlined,
              const Color(0xFFF97316), () => const AdsScreen()),
          _Item('API keys', Icons.vpn_key_outlined, const Color(0xFF64748B),
              () => const ApiKeysScreen()),
          _Item('Support', Icons.help_outline, const Color(0xFF06B6D4),
              () => const SupportScreen()),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return Scaffold(
      appBar: const OkayAppBar(title: Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          for (final s in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Text(s.title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Theme.of(context).colorScheme.outline)),
            ),
            for (final item in s.items)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: item.color.withValues(alpha: 0.15),
                  child: Icon(item.icon, color: item.color),
                ),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => item.builder())),
              ),
          ],
        ],
      ),
    );
  }
}
