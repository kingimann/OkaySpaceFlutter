import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';
import 'profile_screen.dart';

/// Search across people and hashtags.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Future<List<PublicUser>>? _people;
  Future<List<Post>>? _tagged;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _query = q;
      _people = api.users.search(q);
      // Hashtag search uses the tag without a leading '#'.
      _tagged = api.feed.hashtagPosts(q.replaceFirst(RegExp(r'^#'), ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: const InputDecoration(
              hintText: 'Search people & tags',
              border: InputBorder.none,
            ),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: _run),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'People'), Tab(text: 'Tags')],
          ),
        ),
        body: _query.isEmpty
            ? const CenteredMessage(
                message: 'Search for people or hashtags.')
            : TabBarView(
                children: [
                  AsyncList<PublicUser>(
                    future: _people!,
                    emptyMessage: 'No people found.',
                    builder: (context, items) => ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final u = items[i];
                        return ListTile(
                          leading: Avatar(url: u.picture, name: u.name),
                          title: Row(
                            children: [
                              Flexible(child: Text(u.name)),
                              if (u.verified) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified,
                                    size: 14, color: Colors.blue),
                              ],
                            ],
                          ),
                          subtitle:
                              u.username != null ? Text(u.handle) : null,
                          onTap: () => ProfileScreen.open(context, u.userId),
                        );
                      },
                    ),
                  ),
                  AsyncList<Post>(
                    future: _tagged!,
                    emptyMessage: 'No posts for #$_query.',
                    builder: (context, items) => ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => PostTile(post: items[i]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
