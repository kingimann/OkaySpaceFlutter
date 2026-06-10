import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_tile.dart';

/// Posts for a single hashtag.
class HashtagScreen extends StatefulWidget {
  const HashtagScreen({super.key, required this.tag});

  /// The tag without a leading '#'.
  final String tag;

  static Future<void> open(BuildContext context, String tag) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HashtagScreen(tag: tag),
      ));

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  late Future<List<Post>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = api.feed.hashtagPosts(widget.tag);
  }

  Future<void> _reload() async {
    setState(() => _posts = api.feed.hashtagPosts(widget.tag));
    await _posts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(title: Text('#${widget.tag}')),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Post>(
          future: _posts,
          loading: const FeedSkeleton(),
          emptyMessage: 'No posts for #${widget.tag}.',
          emptyIcon: Icons.tag,
          builder: (context, items) => ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: items.length,
            itemBuilder: (context, i) => PostTile(post: items[i], card: true),
          ),
        ),
      ),
      ),
    );
  }
}
