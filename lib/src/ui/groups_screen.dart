import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';

/// Browse the groups the current user can see.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late Future<List<Group>> _groups;

  @override
  void initState() {
    super.initState();
    _groups = api.groups.list();
  }

  Future<void> _reload() async {
    setState(() => _groups = api.groups.list());
    await _groups;
  }

  String _trailingLabel(Group g) {
    if (g.isMember) return 'Joined';
    if (g.membershipPending) return 'Requested';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Group>(
          future: _groups,
          emptyMessage: 'No groups yet.',
          emptyIcon: Icons.group_work_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final g = items[i];
              final label = _trailingLabel(g);
              return ListTile(
                leading: Avatar(name: g.name),
                title: Text(g.name),
                subtitle: Text(
                  '${formatCount(g.memberCount)} members${g.isPrivate ? ' · Private' : ''}',
                ),
                trailing: label.isEmpty ? null : Chip(label: Text(label)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupDetailScreen(groupId: g.id),
                )),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A group's header (join/leave) and its posts.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late Future<Group> _group;
  late Future<List<Post>> _posts;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _group = api.groups.get(widget.groupId);
    _posts = api.groups.posts(widget.groupId);
  }

  Future<void> _reload() async {
    setState(_load);
    await _group;
  }

  Future<void> _toggleMembership(Group g) async {
    setState(() => _working = true);
    try {
      if (g.isMember) {
        await api.groups.leave(g.id);
      } else {
        await api.groups.join(g.id);
      }
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _membershipLabel(Group g) {
    if (g.isMember) return 'Leave';
    if (g.membershipPending) return 'Requested';
    return 'Join';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            FutureBuilder<Group>(
              future: _group,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final g = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Avatar(name: g.name, radius: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge),
                                Text(
                                    '${formatCount(g.memberCount)} members${g.isPrivate ? ' · Private' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: (_working || g.membershipPending)
                                ? null
                                : () => _toggleMembership(g),
                            child: Text(_membershipLabel(g)),
                          ),
                        ],
                      ),
                      if (g.description != null &&
                          g.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(g.description!),
                      ],
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
            FutureBuilder<List<Post>>(
              future: _posts,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final posts = snapshot.data ?? const [];
                if (posts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No posts yet.')),
                  );
                }
                return Column(
                  children: [
                    for (final p in posts) PostTile(post: p, card: true),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
