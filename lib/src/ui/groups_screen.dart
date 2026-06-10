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
  final _search = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _groups = api.groups.list();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _groups = api.groups.list());
    await _groups;
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
      appBar: OkayAppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create group',
            onPressed: _create,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search groups',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _filter = '');
                        }),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Group>(
          future: _groups,
          loading: const ListSkeleton(),
          emptyMessage: 'No groups yet.',
          emptyIcon: Icons.group_work_outlined,
          builder: (context, all) {
            final items = _filter.isEmpty
                ? all
                : all
                    .where((g) => g.name.toLowerCase().contains(_filter))
                    .toList();
            return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount: items.length,
            itemBuilder: (context, i) => _GroupCard(
                key: ValueKey(items[i].id),
                group: items[i],
                onChanged: _reload),
          );
          },
        ),
      ),
      ),
    );
  }
}

Color _groupColor(Group g, BuildContext context) {
  final hex = g.color.replaceFirst('#', '');
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return Theme.of(context).colorScheme.primary;
}

/// A group list card: avatar, member count, description preview, and an inline
/// join/requested/joined action.
class _GroupCard extends StatefulWidget {
  const _GroupCard(
      {super.key, required this.group, required this.onChanged});

  final Group group;
  final VoidCallback onChanged;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late bool _member = widget.group.isMember;
  late bool _pending = widget.group.membershipPending;
  late int _members = widget.group.memberCount;

  Group get g => widget.group;

  Future<void> _join() async {
    if (_member || _pending) {
      // Leave.
      final wasMembers = _members;
      setState(() {
        _member = false;
        _pending = false;
        _members = (wasMembers - 1).clamp(0, 1 << 30);
      });
      try {
        await api.groups.leave(g.id);
        widget.onChanged();
      } catch (e) {
        if (mounted) {
          setState(() {
            _member = true;
            _members = wasMembers;
          });
          showError(context, e);
        }
      }
      return;
    }
    // Join (private groups become "requested").
    setState(() {
      if (g.isPrivate) {
        _pending = true;
      } else {
        _member = true;
        _members += 1;
      }
    });
    try {
      await api.groups.join(g.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() {
          _member = false;
          _pending = false;
          _members = widget.group.memberCount;
        });
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _groupColor(g, context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GroupDetailScreen(groupId: g.id),
        )),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: color,
                    child: Text(
                      g.name.isNotEmpty ? g.name[0].toUpperCase() : '#',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                                g.isPrivate
                                    ? Icons.lock_outline
                                    : Icons.public,
                                size: 13,
                                color: scheme.outline),
                            const SizedBox(width: 4),
                            Text(
                                '${formatCount(_members)} members · '
                                '${g.isPrivate ? 'Private' : 'Public'}',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 12.5)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (g.description != null && g.description!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(g.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _pending
                    ? OutlinedButton.icon(
                        onPressed: _join,
                        icon: const Icon(Icons.hourglass_top, size: 18),
                        label: const Text('Requested'),
                      )
                    : _member
                        ? OutlinedButton.icon(
                            onPressed: _join,
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Joined'),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: _join,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(g.isPrivate ? 'Request to join' : 'Join group'),
                          ),
              ),
            ],
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

  Future<void> _editGroup(Group g) async {
    final name = TextEditingController(text: g.name);
    final desc = TextEditingController(text: g.description ?? '');
    bool private = g.isPrivate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit group'),
        content: StatefulBuilder(
          builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: desc,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Description', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                value: private,
                onChanged: (v) => setLocal(() => private = v),
                title: const Text('Private group'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.groups.update(g.id, {
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'is_private': private,
      });
      if (mounted) showInfo(context, 'Group updated');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteGroup(Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('“${g.name}” and its posts will be removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.groups.delete(g.id);
      if (mounted) {
        showInfo(context, 'Group deleted');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
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

  /// A small rounded stat chip (members / privacy) for the header.
  Widget _statChip(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.outline),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
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
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Members',
            onPressed: () async {
              final g = await _group;
              if (!context.mounted) return;
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _GroupMembersScreen(
                    groupId: widget.groupId, canManage: g.canManage),
              ));
              _reload();
            },
          ),
          FutureBuilder<Group>(
            future: _group,
            builder: (context, snap) {
              final g = snap.data;
              if (g == null || !g.canManage) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _editGroup(g);
                  if (v == 'delete') _deleteGroup(g);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit group')),
                  PopupMenuItem(value: 'delete', child: Text('Delete group')),
                ],
              );
            },
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
                final color = _groupColor(g, context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Colored banner with the group avatar overlapping it.
                    SizedBox(
                      height: 116,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            height: 84,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, darken(color, 0.25)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).scaffoldBackgroundColor,
                              ),
                              child: CircleAvatar(
                                radius: 32,
                                backgroundColor: color,
                                child: Text(
                                  g.name.isNotEmpty
                                      ? g.name[0].toUpperCase()
                                      : '#',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 26),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(g.name,
                              softWrap: true,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _statChip(context, Icons.people_outline,
                                  '${formatCount(g.memberCount)} members'),
                              _statChip(
                                  context,
                                  g.isPrivate
                                      ? Icons.lock_outline
                                      : Icons.public,
                                  g.isPrivate ? 'Private' : 'Public'),
                            ],
                          ),
                          if (g.description != null &&
                              g.description!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(g.description!),
                          ],
                          const SizedBox(height: 14),
                          FilledButton.tonal(
                            onPressed: (_working || g.membershipPending)
                                ? null
                                : () => _toggleMembership(g),
                            child: Text(_membershipLabel(g)),
                          ),
                        ],
                      ),
                    ),
                  ],
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

/// Group members with manager actions (promote/demote/remove).
class _GroupMembersScreen extends StatefulWidget {
  const _GroupMembersScreen({required this.groupId, this.canManage = false});

  final String groupId;
  final bool canManage;

  @override
  State<_GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<_GroupMembersScreen> {
  late Future<List<Map<String, dynamic>>> _members;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _members = api.groups.members(widget.groupId).then((d) {
      final list = d is Map ? (d['members'] ?? d['items'] ?? d['users']) : d;
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    });
  }

  Future<void> _act(String userId, Future<void> Function() op, String ok) async {
    try {
      await op();
      if (mounted) showInfo(context, ok);
      setState(_load);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Members')),
      body: MaxWidth(
        child: AsyncList<Map<String, dynamic>>(
          future: _members,
          emptyMessage: 'No members yet.',
          emptyIcon: Icons.people_outline,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = items[i];
              final id = '${m['user_id'] ?? m['id'] ?? ''}';
              final name = '${m['name'] ?? m['user_name'] ?? 'Member'}';
              final role = '${m['role'] ?? m['my_role'] ?? ''}';
              final isAdmin = role == 'admin' || role == 'owner';
              return ListTile(
                leading: Avatar(url: '${m['picture'] ?? ''}', name: name),
                title: Text(name),
                subtitle: role.isNotEmpty ? Text(role) : null,
                trailing: widget.canManage && id.isNotEmpty && role != 'owner'
                    ? PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'promote') {
                            _act(
                                id,
                                () => api.groups
                                    .promoteMember(widget.groupId, id),
                                'Promoted');
                          } else if (v == 'demote') {
                            _act(
                                id,
                                () => api.groups
                                    .demoteMember(widget.groupId, id),
                                'Demoted');
                          } else if (v == 'remove') {
                            _act(
                                id,
                                () => api.groups
                                    .removeMember(widget.groupId, id),
                                'Removed');
                          }
                        },
                        itemBuilder: (_) => [
                          if (!isAdmin)
                            const PopupMenuItem(
                                value: 'promote', child: Text('Make admin')),
                          if (isAdmin)
                            const PopupMenuItem(
                                value: 'demote', child: Text('Remove admin')),
                          const PopupMenuItem(
                              value: 'remove', child: Text('Remove member')),
                        ],
                      )
                    : null,
              );
            },
          ),
        ),
      ),
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
      appBar: const OkayAppBar(title: Text('Join requests')),
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
