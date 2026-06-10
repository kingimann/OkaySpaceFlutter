import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'profile_screen.dart';

/// Followers / Following lists for a user.
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({
    super.key,
    required this.userId,
    this.initialIndex = 0,
  });

  final String userId;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Connections'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Followers'), Tab(text: 'Following')],
          ),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [
              _UserList(
                  future: api.users.followers(userId),
                  empty: 'No followers yet.'),
              _UserList(
                  future: api.users.following(userId),
                  empty: 'Not following anyone yet.'),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({required this.future, required this.empty});

  final Future<List<PublicUser>> future;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return AsyncList<PublicUser>(
      future: future,
      emptyMessage: empty,
      emptyIcon: Icons.people_outline,
      builder: (context, items) => ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final u = items[i];
          return ListTile(
            leading: Avatar(url: u.picture, name: u.name),
            title: Row(
              children: [
                Flexible(child: Text(u.name, overflow: TextOverflow.ellipsis)),
                if (u.verified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, size: 14, color: Colors.blue),
                ],
              ],
            ),
            subtitle: u.username != null ? Text(u.handle) : null,
            onTap: () => ProfileScreen.open(context, u.userId),
          );
        },
      ),
    );
  }
}
