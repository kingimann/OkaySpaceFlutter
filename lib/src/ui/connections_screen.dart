import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'profile_screen.dart';

/// Followers / Following lists for a user.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    required this.userId,
    this.initialIndex = 0,
  });

  final String userId;
  final int initialIndex;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  // Cached once so rebuilds don't refetch and flicker the lists.
  late final Future<List<PublicUser>> _followers =
      api.users.followers(widget.userId);
  late final Future<List<PublicUser>> _following =
      api.users.following(widget.userId);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialIndex,
      child: Scaffold(
        appBar: const OkayAppBar(
          title: Text('Connections'),
          bottom: TabBar(
            tabs: [Tab(text: 'Followers'), Tab(text: 'Following')],
          ),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [
              _UserList(future: _followers, empty: 'No followers yet.'),
              _UserList(
                  future: _following, empty: 'Not following anyone yet.'),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserList extends StatefulWidget {
  const _UserList({required this.future, required this.empty});

  final Future<List<PublicUser>> future;
  final String empty;

  @override
  State<_UserList> createState() => _UserListState();
}

class _UserListState extends State<_UserList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: AsyncList<PublicUser>(
            future: widget.future,
            emptyMessage: widget.empty,
            emptyIcon: Icons.people_outline,
            builder: (context, all) {
              final items = _query.isEmpty
                  ? all
                  : all
                      .where((u) =>
                          u.name.toLowerCase().contains(_query) ||
                          (u.username ?? '').toLowerCase().contains(_query))
                      .toList();
              if (items.isEmpty) {
                return const CenteredMessage(
                    message: 'No matches.', icon: Icons.search_off);
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final u = items[i];
                  return ListTile(
                    leading: Avatar(url: u.picture, name: u.name),
                    title: Row(
                      children: [
                        Flexible(
                            child:
                                Text(u.name, overflow: TextOverflow.ellipsis)),
                        if (u.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 14, color: Color(0xFF3B82F6)),
                        ],
                      ],
                    ),
                    subtitle: u.username != null ? Text(u.handle) : null,
                    onTap: () => ProfileScreen.open(context, u.userId),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
