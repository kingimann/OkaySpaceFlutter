import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Audience circles — private groupings of people you can target a post to.
class CirclesScreen extends StatefulWidget {
  const CirclesScreen({super.key});

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> {
  late Future<List<Map<String, dynamic>>> _circles;

  @override
  void initState() {
    super.initState();
    _circles = api.circles.circles();
  }

  Future<void> _reload() async {
    setState(() => _circles = api.circles.circles());
    await _circles;
  }

  int _count(Map<String, dynamic> c) {
    final m = c['member_ids'] ?? c['members'] ?? c['member_count'];
    if (m is List) return m.length;
    if (m is num) return m.toInt();
    return 0;
  }

  Future<void> _create() async {
    final name = await promptText(context,
        title: 'New circle',
        hint: 'e.g. Close friends',
        action: 'Create');
    if (name == null) return;
    try {
      await api.circles.create(name: name);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename(Map<String, dynamic> c) async {
    final name = await promptText(context,
        title: 'Rename circle', action: 'Save', initial: '${c['name'] ?? ''}');
    if (name == null) return;
    try {
      await api.circles.update('${c['id']}', name: name);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete circle?'),
        content: Text('“${c['name'] ?? 'Circle'}” will be removed.'),
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
      await api.circles.delete('${c['id']}');
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Add a person (by search) to a circle.
  Future<void> _addMember(Map<String, dynamic> c) async {
    final query = await promptText(context,
        title: 'Add to ${c['name'] ?? 'circle'}',
        hint: 'Search people',
        action: 'Search');
    if (query == null) return;
    try {
      final results = await api.users.search(query);
      if (!mounted) return;
      if (results.isEmpty) {
        showInfo(context, 'No people found.');
        return;
      }
      final user = await showModalBottomSheet<PublicUser>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final u in results)
                ListTile(
                  leading: Avatar(url: u.picture, name: u.name),
                  title: Text(u.name),
                  subtitle: u.username != null ? Text(u.handle) : null,
                  onTap: () => Navigator.pop(context, u),
                ),
            ],
          ),
        ),
      );
      if (user == null) return;
      await api.circles.update('${c['id']}', addMemberIds: [user.userId]);
      if (mounted) {
        showInfo(context, 'Added ${user.name}');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Circles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New circle'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _circles,
            loading: const ListSkeleton(),
            emptyMessage:
                'No circles yet.\nGroup people to share posts privately.',
            emptyIcon: Icons.group_work_outlined,
            builder: (context, items) => ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final c = items[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primary.withValues(alpha: 0.16),
                      child: Icon(Icons.lock_outline, color: scheme.primary),
                    ),
                    title: Text('${c['name'] ?? 'Circle'}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${_count(c)} ${_count(c) == 1 ? 'person' : 'people'}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'add') _addMember(c);
                        if (v == 'rename') _rename(c);
                        if (v == 'delete') _delete(c);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'add', child: Text('Add person')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () => _addMember(c),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
