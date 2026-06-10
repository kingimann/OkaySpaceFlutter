import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';

/// The current user's bookmarked posts.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<Post>> _bookmarks;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _bookmarks = api.feed.bookmarks();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _bookmarks = api.feed.bookmarks());
    await _bookmarks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Bookmarks')),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search bookmarks',
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
              child: RefreshIndicator(
                onRefresh: _reload,
                child: AsyncList<Post>(
                  future: _bookmarks,
                  loading: const FeedSkeleton(),
                  emptyMessage:
                      'No bookmarks yet.\nTap the bookmark icon on a post.',
                  emptyIcon: Icons.bookmark_border,
                  builder: (context, all) {
                    final items = _query.isEmpty
                        ? all
                        : all
                            .where((p) =>
                                p.text.toLowerCase().contains(_query) ||
                                (p.author.name.toLowerCase().contains(_query)))
                            .toList();
                    if (items.isEmpty) {
                      return const CenteredMessage(
                          message: 'No matching bookmarks.',
                          icon: Icons.search_off);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (context, i) =>
                          PostTile(post: items[i], card: true),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
