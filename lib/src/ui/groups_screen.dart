import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'group_events_screen.dart';
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

  Future<void> _create() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (id == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupDetailScreen(groupId: id),
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create group',
            onPressed: _create,
          ),
        ],
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Group>(
          future: _groups,
          loading: const ListSkeleton(),
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

  Future<void> _composePost() async {
    final text = await promptText(context,
        title: 'Post to group', hint: "What's happening?");
    if (text == null) return;
    try {
      await api.groups.createPost(widget.groupId, PostCreate(text: text));
      if (mounted) {
        showInfo(context, 'Posted');
        setState(() => _posts = api.groups.posts(widget.groupId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group'),
        actions: [
          FutureBuilder<Group>(
            future: _group,
            builder: (context, snap) {
              final g = snap.data;
              if (g == null || !g.canManage) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Join requests',
                icon: Badge(
                  isLabelVisible: g.pendingRequestCount > 0,
                  label: Text('${g.pendingRequestCount}'),
                  child: const Icon(Icons.how_to_reg_outlined),
                ),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _GroupRequestsScreen(groupId: widget.groupId),
                  ));
                  _reload();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: 'Events',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GroupEventsScreen(groupId: widget.groupId),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _composePost,
        child: const Icon(Icons.edit),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
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
      ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _private = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final g = await api.groups.create(
        name: _name.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        isPrivate: _private,
      );
      if (mounted) Navigator.pop(context, g.id);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          StatefulBuilder(
            builder: (context, setLocal) => SwitchListTile(
              value: _private,
              onChanged: (v) => setLocal(() => setState(() => _private = v)),
              title: const Text('Private group'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}

/// Pending join requests for a group (manager view): approve or reject.
class _GroupRequestsScreen extends StatefulWidget {
  const _GroupRequestsScreen({required this.groupId});

  final String groupId;

  @override
  State<_GroupRequestsScreen> createState() => _GroupRequestsScreenState();
}

class _GroupRequestsScreenState extends State<_GroupRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _requests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requests = api.groups.joinRequests(widget.groupId).then((d) {
      final list = d is Map ? (d['requests'] ?? d['items'] ?? d['users']) : d;
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    });
  }

  Future<void> _act(String userId, bool approve) async {
    try {
      if (approve) {
        await api.groups.approveRequest(widget.groupId, userId);
      } else {
        await api.groups.rejectRequest(widget.groupId, userId);
      }
      setState(_load);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join requests')),
      body: AsyncList<Map<String, dynamic>>(
        future: _requests,
        emptyMessage: 'No pending requests.',
        emptyIcon: Icons.how_to_reg_outlined,
        builder: (context, items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = items[i];
            final id = '${r['user_id'] ?? r['id'] ?? ''}';
            final name = '${r['name'] ?? r['user_name'] ?? 'User'}';
            return ListTile(
              leading: Avatar(
                  url: '${r['picture'] ?? r['user_picture'] ?? ''}', name: name),
              title: Text(name),
              subtitle: r['username'] != null ? Text('@${r['username']}') : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: id.isEmpty ? null : () => _act(id, true),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: id.isEmpty ? null : () => _act(id, false),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
