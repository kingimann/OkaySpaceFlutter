import 'package:flutter/material.dart';

import 'common.dart';
import 'compose_screen.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';

/// A right-side navigation drawer (the Scaffold `endDrawer`) with quick access
/// to the destinations that aren't on the bottom bar. Opens by swiping from the
/// right edge or via the top-right button. Destinations push into the shell's
/// nested content navigator so the bottom nav stays visible.
class RightSidebar extends StatelessWidget {
  const RightSidebar({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // close the endDrawer
    contentNavigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: kPrimaryRouteName),
      builder: (_) => screen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ListTile tile(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(label),
          onTap: onTap,
        );
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Shortcuts',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
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
