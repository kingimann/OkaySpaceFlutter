import 'package:flutter/material.dart';

import 'bookmarks_screen.dart';
import 'communities_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'roadside_screen.dart';
import 'support_screen.dart';
import 'wallet_screen.dart';

/// Side menu opened from the feed header's hamburger — quick access to the
/// areas that aren't bottom-nav tabs.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(IconData icon, String label, Widget screen) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => screen));
          },
        );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  Icon(Icons.public, color: scheme.primary, size: 30),
                  const SizedBox(width: 10),
                  Text('OkaySpace',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            item(Icons.people_alt_outlined, 'Friends', const FriendsScreen()),
            item(Icons.groups_outlined, 'Communities',
                const CommunitiesScreen()),
            item(Icons.group_work_outlined, 'Groups', const GroupsScreen()),
            item(Icons.account_balance_wallet_outlined, 'Wallet',
                const WalletScreen()),
            item(Icons.bookmark_border, 'Bookmarks', const BookmarksScreen()),
            item(Icons.car_repair, 'Roadside assistance',
                const RoadsideScreen()),
            item(Icons.support_agent_outlined, 'Support',
                const SupportScreen()),
          ],
        ),
      ),
    );
  }
}
