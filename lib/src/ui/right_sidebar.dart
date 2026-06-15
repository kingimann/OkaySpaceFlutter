import 'package:flutter/material.dart';

import 'common.dart';
import 'compose_screen.dart';
import 'feed_prefs.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';

/// A right-side navigation drawer (the Scaffold `endDrawer`) with the feed
/// controls (Explore / Following / Customize) and quick access to the
/// destinations that aren't on the bottom bar. Opens by swiping from the right
/// edge or via the top-right button. Destinations push into the shell's nested
/// content navigator so the bottom nav stays visible.
class RightSidebar extends StatelessWidget {
  const RightSidebar({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // close the endDrawer
    contentNavigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: kPrimaryRouteName),
      builder: (_) => screen,
    ));
  }

  /// Shows the feed and selects the Explore (0) / Following (1) tab.
  void _goFeedTab(BuildContext context, int idx) {
    Navigator.of(context).pop(); // close the endDrawer
    homeTabSignal.select('feed');
    feedTabSignal.value = idx;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            t,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: scheme.outline),
          ),
        );
    ListTile tile(IconData icon, String label, VoidCallback onTap,
            {Widget? trailing}) =>
        ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(label),
          trailing: trailing,
          onTap: onTap,
        );
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            header('Feed'),
            ValueListenableBuilder<int>(
              valueListenable: feedTabSignal,
              builder: (context, tab, _) => Column(
                children: [
                  tile(Icons.explore_outlined, 'Explore',
                      () => _goFeedTab(context, 0),
                      trailing: tab == 0
                          ? Icon(Icons.check, color: scheme.primary)
                          : null),
                  tile(Icons.group_outlined, 'Following',
                      () => _goFeedTab(context, 1),
                      trailing: tab == 1
                          ? Icon(Icons.check, color: scheme.primary)
                          : null),
                ],
              ),
            ),
            tile(Icons.tune, 'Customize feed',
                () => _open(context, const FeedPrefsScreen())),
            const Divider(height: 12),
            header('Shortcuts'),
            tile(Icons.edit_outlined, 'Create post',
                () => _open(context, const ComposeScreen())),
            tile(Icons.forum_outlined, 'Messages',
                () => _open(context, const MessagesScreen())),
            tile(Icons.notifications_none, 'Notifications',
                () => _open(context, const NotificationsScreen())),
            tile(Icons.search, 'Search',
                () => _open(context, const SearchScreen())),
          ],
        ),
      ),
    );
  }
}
