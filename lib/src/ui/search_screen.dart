import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'hashtag_screen.dart';
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
        body: MaxWidth(
          child: _query.isEmpty
            ? _TrendingHashtags()
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
                    builder: (context, items) => ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (context, i) =>
                          PostTile(post: items[i], card: true),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

/// Shown before searching: the currently trending hashtags.
class _TrendingHashtags extends StatefulWidget {
  @override
  State<_TrendingHashtags> createState() => _TrendingHashtagsState();
}

class _TrendingHashtagsState extends State<_TrendingHashtags> {
  late Future<List<Map<String, dynamic>>> _trending;

  @override
  void initState() {
    super.initState();
    _trending = api.feed.trendingHashtags();
  }

  String _tagOf(Map<String, dynamic> m) =>
      '${m['tag'] ?? m['name'] ?? m['hashtag'] ?? ''}'.replaceFirst('#', '');

  int _countOf(Map<String, dynamic> m) {
    final v = m['count'] ?? m['posts'] ?? m['post_count'];
    return v is num ? v.toInt() : 0;
  }

  @override
  Widget build(BuildContext context) {
    return AsyncList<Map<String, dynamic>>(
      future: _trending,
      emptyMessage: 'Search for people or hashtags.',
      emptyIcon: Icons.search,
      builder: (context, items) {
        final tags = [for (final m in items) if (_tagOf(m).isNotEmpty) m];
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Row(
                children: [
                  Icon(Icons.trending_up,
                      color: Theme.of(context).colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  const Text('Trending',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
            for (var i = 0; i < tags.length; i++)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                ),
                title: Text('#${_tagOf(tags[i])}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: _countOf(tags[i]) > 0
                    ? Text('${formatCount(_countOf(tags[i]))} posts')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => HashtagScreen.open(context, _tagOf(tags[i])),
              ),
          ],
        );
      },
    );
  }
}
