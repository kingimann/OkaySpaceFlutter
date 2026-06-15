import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'engagement_sheet.dart';
import 'post_tile.dart';

/// A single post shown in full with its replies and a reply composer.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  static Future<void> open(BuildContext context, Post post) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post),
      ));

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Post _post;
  late Future<List<Post>> _replies;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _replies = api.feed.replies(_post.id);
    // Refresh the post itself for up-to-date counts.
    api.feed.getPost(_post.id).then((p) {
      if (mounted) setState(() => _post = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _reloadReplies() async {
    setState(() => _replies = api.feed.replies(_post.id));
    await _replies;
  }

  /// Re-fetch the focused post after a ⋯ menu action (edit/pin); if it was
  /// deleted, leave the now-empty detail screen.
  void _refreshPost() {
    api.feed.getPost(_post.id).then((p) {
      if (mounted) setState(() => _post = p);
    }).catchError((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _sendReply() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await api.feed.reply(_post.id, text);
      _input.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _reloadReplies();
      // Bump the local reply count.
      api.feed.getPost(_post.id).then((p) {
        if (mounted) setState(() => _post = p);
      }).catchError((_) {});
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Post')),
      body: MaxWidth(
        child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reloadReplies,
              child: ListView(
                children: [
                  // The focused post, rendered in the same card style as the
                  // newsfeed. The comment button focuses the reply box below
                  // instead of opening another detail screen.
                  PostTile(
                    post: _post,
                    tappable: false,
                    card: true,
                    onComment: () => _inputFocus.requestFocus(),
                    onChanged: _refreshPost,
                  ),
                  if (_post.userId == currentUserId)
                    Container(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(Icons.bar_chart,
                            color: Theme.of(context).colorScheme.outline),
                        title: const Text('View insights'),
                        subtitle:
                            Text('${formatCount(_post.viewsCount)} views'),
                        trailing: Icon(Icons.chevron_right,
                            color: Theme.of(context).colorScheme.outline),
                        onTap: () => showPostInsightsSheet(context, _post.id),
                      ),
                    ),
                  const SizedBox(height: 2),
                  FutureBuilder<List<Post>>(
                    future: _replies,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                              child: Text(messageFor(snapshot.error))),
                        );
                      }
                      final replies = snapshot.data ?? const [];
                      if (replies.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No replies yet.')),
                        );
                      }
                      // The author's own follow-ups read as a continuation of
                      // the thread, so surface them first; everyone else's
                      // replies sit below a labelled separator.
                      final threadParts = replies
                          .where((r) => r.userId == _post.userId)
                          .toList();
                      final others = replies
                          .where((r) => r.userId != _post.userId)
                          .toList();
                      return Column(
                        children: [
                          const SizedBox(height: 4),
                          for (final r in threadParts)
                            PostTile(post: r, compact: true, card: true),
                          if (others.isNotEmpty) ...[
                            if (threadParts.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('Replies',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline)),
                                ),
                              ),
                            for (final r in others)
                              PostTile(post: r, compact: true, card: true),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendReply(),
                      decoration: const InputDecoration(
                        hintText: 'Post your reply',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _sendReply,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
