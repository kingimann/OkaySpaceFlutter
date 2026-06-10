import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'profile_screen.dart';

/// Friends list + incoming requests, with an add-friend search.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late Future<List<PublicUser>> _friends;
  late Future<List<PublicUser>> _requests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _friends = api.friends.friends();
    _requests = api.friends.requests();
  }

  Future<void> _reload() async {
    setState(_load);
    await Future.wait([_friends, _requests]);
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addFriend() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const _AddFriendScreen(),
    ));
    if (sent == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: OkayAppBar(
          title: const Text('Friends'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Add friend',
              onPressed: _addFriend,
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Friends'), Tab(text: 'Requests')],
          ),
        ),
        body: MaxWidth(
          child: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _reload,
              child: AsyncList<PublicUser>(
                future: _friends,
                loading: const ListSkeleton(),
                emptyMessage: 'No friends yet.\nTap + to add someone.',
                emptyIcon: Icons.people_outline,
                builder: (context, items) => ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = items[i];
                    return ListTile(
                      leading: Avatar(url: u.picture, name: u.name),
                      title: Text(u.name),
                      subtitle: u.username != null ? Text(u.handle) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.person_remove_outlined),
                        tooltip: 'Remove',
                        onPressed: () =>
                            _act(() => api.friends.remove(u.userId)),
                      ),
                      onTap: () => ProfileScreen.open(context, u.userId),
                    );
                  },
                ),
              ),
            ),
            RefreshIndicator(
              onRefresh: _reload,
              child: AsyncList<PublicUser>(
                future: _requests,
                emptyMessage: 'No pending requests.',
                emptyIcon: Icons.mark_email_read_outlined,
                builder: (context, items) => ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = items[i];
                    return ListTile(
                      leading: Avatar(url: u.picture, name: u.name),
                      title: Text(u.name),
                      subtitle: u.username != null ? Text(u.handle) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle,
                                color: Colors.green),
                            tooltip: 'Accept',
                            onPressed: () =>
                                _act(() => api.friends.accept(u.userId)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Reject',
                            onPressed: () =>
                                _act(() => api.friends.reject(u.userId)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Search users and send friend requests.
class _AddFriendScreen extends StatefulWidget {
  const _AddFriendScreen();

  @override
  State<_AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<_AddFriendScreen> {
  final _search = TextEditingController();
  Future<List<PublicUser>>? _results;
  final _sentTo = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = api.users.search(q));
  }

  Future<void> _send(PublicUser u) async {
    try {
      await api.friends.sendRequest(u.userId);
      setState(() => _sentTo.add(u.userId));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: TextField(
          controller: _search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: const InputDecoration(
              hintText: 'Search people', border: InputBorder.none),
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: _run)],
      ),
      body: _results == null
          ? const CenteredMessage(
              message: 'Search for people to add.', icon: Icons.search)
          : AsyncList<PublicUser>(
              future: _results!,
              emptyMessage: 'No people found.',
              emptyIcon: Icons.person_search_outlined,
              builder: (context, items) => ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final u = items[i];
                  final sent = _sentTo.contains(u.userId);
                  return ListTile(
                    leading: Avatar(url: u.picture, name: u.name),
                    title: Text(u.name),
                    subtitle: u.username != null ? Text(u.handle) : null,
                    trailing: sent
                        ? const Chip(label: Text('Requested'))
                        : FilledButton.tonal(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40)),
                            onPressed: () => _send(u),
                            child: const Text('Add'),
                          ),
                  );
                },
              ),
            ),
    );
  }
}
