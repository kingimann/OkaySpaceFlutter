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

  @override
  void initState() {
    super.initState();
    _bookmarks = api.feed.bookmarks();
  }

  Future<void> _reload() async {
    setState(() => _bookmarks = api.feed.bookmarks());
    await _bookmarks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Post>(
          future: _bookmarks,
          emptyMessage: 'No bookmarks yet.\nTap the bookmark icon on a post.',
          emptyIcon: Icons.bookmark_border,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => PostTile(post: items[i]),
          ),
        ),
      ),
    );
  }
}
