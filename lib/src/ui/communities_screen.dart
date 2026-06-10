import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';

Color _communityColor(Community c, BuildContext context) {
  final hex = c.color.replaceFirst('#', '');
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return Theme.of(context).colorScheme.primary;
}

/// Browse and search communities.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  late Future<List<Community>> _communities;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _query() {
    final q = _search.text.trim();
    _communities = api.communities.list(query: q.isEmpty ? null : q);
  }

  Future<void> _reload() async {
    setState(_query);
    await _communities;
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateCommunityDialog(),
    );
    if (name == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(name: name),
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create community',
            onPressed: _create,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Search communities',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward), onPressed: _reload),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Community>(
          future: _communities,
          loading: const ListSkeleton(),
          emptyMessage: 'No communities found.',
          emptyIcon: Icons.groups_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = items[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _communityColor(c, context),
                  child: Text(
                    c.title.isNotEmpty ? c.title[0].toUpperCase() : '#',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(c.title),
                subtitle: Text(
                    '${formatCount(c.memberCount)} members · ${formatCount(c.postCount)} posts'),
                trailing: c.isMember
                    ? const Chip(label: Text('Joined'))
                    : null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CommunityDetailScreen(name: c.name),
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

/// A community's header (with join/leave) and its posts.
class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({super.key, required this.name});

  final String name;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  late Future<Community> _community;
  late Future<List<Post>> _posts;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _community = api.communities.get(widget.name);
    _posts = api.communities.posts(widget.name);
  }

  Future<void> _reload() async {
    setState(_load);
    await _community;
  }

  Future<void> _toggleMembership(Community c) async {
    setState(() => _working = true);
    try {
      if (c.isMember) {
        await api.communities.leave(c.name);
      } else {
        await api.communities.join(c.name);
      }
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _composePost() async {
    final text = await promptText(context,
        title: 'Post to c/${widget.name}', hint: "What's happening?");
    if (text == null) return;
    try {
      final c = await _community;
      await api.feed.createPost(PostCreate(text: text, communityId: c.id));
      if (mounted) {
        showInfo(context, 'Posted');
        setState(() => _posts = api.communities.posts(widget.name));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: _composePost,
        child: const Icon(Icons.edit),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            FutureBuilder<Community>(
              future: _community,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final c = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: _communityColor(c, context),
                            child: Text(
                              c.title.isNotEmpty
                                  ? c.title[0].toUpperCase()
                                  : '#',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge),
                                Text(
                                    '${formatCount(c.memberCount)} members',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed:
                                _working ? null : () => _toggleMembership(c),
                            child: Text(c.isMember ? 'Leave' : 'Join'),
                          ),
                        ],
                      ),
                      if (c.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(c.description),
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

class _CreateCommunityDialog extends StatefulWidget {
  const _CreateCommunityDialog();

  @override
  State<_CreateCommunityDialog> createState() => _CreateCommunityDialogState();
}

class _CreateCommunityDialogState extends State<_CreateCommunityDialog> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final c = await api.communities.create(
        name: name,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      if (mounted) Navigator.pop(context, c.name);
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
      title: const Text('Create community'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name (no spaces)',
                prefixText: 'c/',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Display title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder()),
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
