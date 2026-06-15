import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'compose_screen.dart';
import 'feed_prefs.dart';
import 'linked_text.dart';
import 'post_detail_screen.dart';
import 'post_video.dart';
import 'profile_screen.dart';

/// Opens the post overflow menu. Own posts get edit/pin/delete; [onChanged]
/// is invoked after a mutating action so the host can refresh. Bookmarking
/// lives here too — [bookmarked] reflects the tile's optimistic state and
/// [onBookmark] toggles it.
Future<void> _showPostMenu(BuildContext context, Post post,
    {VoidCallback? onChanged,
    bool bookmarked = false,
    VoidCallback? onBookmark}) async {
  final mine = currentUserId != null && post.author.userId == currentUserId;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      Widget label(String t) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Text(t.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: scheme.outline)),
          );
      Widget tile(IconData icon, String text, String value,
          {bool danger = false}) {
        return SizedBox(
          width: 80,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(sheetCtx, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: danger
                          ? scheme.errorContainer
                          : scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon,
                        color: danger ? scheme.error : scheme.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Post'),
              Wrap(
                children: [
                  tile(Icons.link, 'Copy link', 'copy'),
                  if (post.text.trim().isNotEmpty)
                    tile(Icons.content_copy, 'Copy text', 'copytext'),
                  tile(Icons.forward_to_inbox_outlined, 'Share', 'share'),
                  tile(bookmarked ? Icons.bookmark : Icons.bookmark_border,
                      bookmarked ? 'Unsave' : 'Bookmark', 'bookmark'),
                ],
              ),
              if (mine) ...[
                const SizedBox(height: 8),
                label('Manage'),
                Wrap(
                  children: [
                    tile(Icons.edit_outlined, 'Edit', 'edit'),
                    tile(
                        post.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        post.pinned ? 'Unpin' : 'Pin',
                        'pin'),
                    tile(Icons.campaign_outlined, 'Promote', 'promote'),
                    tile(Icons.delete_outline, 'Delete', 'delete',
                        danger: true),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                label('Actions'),
                Wrap(
                  children: [
                    tile(Icons.not_interested, 'Not interested',
                        'not_interested'),
                    tile(
                        Icons.volume_off_outlined,
                        feedPrefs.isAuthorMuted(post.author.userId)
                            ? 'Unmute'
                            : 'Mute',
                        'mute_author'),
                    tile(Icons.flag_outlined, 'Report', 'report'),
                    // Moderators can remove anyone's post; the backend
                    // re-checks the role, so this only surfaces the action.
                    if (currentUserIsStaff)
                      tile(Icons.gavel_outlined, 'Remove', 'admin_delete',
                          danger: true),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  try {
    switch (action) {
      case 'copy':
        await Clipboard.setData(
            ClipboardData(text: 'https://okayspace.ca/post/${post.id}'));
        if (context.mounted) showInfo(context, 'Link copied');
      case 'copytext':
        await Clipboard.setData(ClipboardData(text: post.text));
        if (context.mounted) showInfo(context, 'Text copied');
      case 'share':
        await _sharePostToChat(context, post);
      case 'bookmark':
        onBookmark?.call();
        if (context.mounted) {
          showInfo(context, bookmarked ? 'Bookmark removed' : 'Bookmarked');
        }
      case 'not_interested':
        await api.feed.notInterested(post.id);
        if (context.mounted) showInfo(context, "We'll show less like this");
      case 'mute_author':
        if (feedPrefs.isAuthorMuted(post.author.userId)) {
          feedPrefs.unmuteAuthor(post.author.userId);
          if (context.mounted) showInfo(context, 'Unmuted ${post.author.name}');
        } else {
          feedPrefs.muteAuthor(post.author.userId, post.author.name);
          if (context.mounted) {
            showInfo(context,
                '${post.author.name} muted — manage in Customize feed');
          }
        }
      case 'report':
        if (context.mounted) await _reportPost(context, post);
      case 'pin':
        await api.feed.togglePin(post.id);
        onChanged?.call();
      case 'promote':
        if (context.mounted) await _promotePost(context, post);
      case 'delete':
        await api.feed.deletePost(post.id);
        if (context.mounted) showInfo(context, 'Deleted');
        onChanged?.call();
      case 'admin_delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this post?'),
            content: Text(
                'Remove @${post.author.username ?? post.author.name}\'s '
                'post as a moderator? This can\'t be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(dialogContext).colorScheme.error),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await api.feed.deletePost(post.id);
          if (context.mounted) showInfo(context, 'Post removed');
          onChanged?.call();
        }
      case 'edit':
        if (!context.mounted) return;
        final text = await promptText(context,
            title: 'Edit post', hint: 'Update your post', action: 'Save');
        if (text == null) return;
        await api.feed.editPost(post.id, {'text': text});
        onChanged?.call();
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

String _convName(ConversationView c) {
  if (c.name != null && c.name!.isNotEmpty) return c.name!;
  if (c.otherUser != null) return c.otherUser!.name;
  if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
  return 'Conversation';
}

/// Shares a post into a conversation the user picks (sent as a post message).
Future<void> _sharePostToChat(BuildContext context, Post post) async {
  final convs = await api.messaging
      .conversations()
      .catchError((_) => <ConversationView>[]);
  if (!context.mounted) return;
  final target = await showModalBottomSheet<ConversationView>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
              title: Text('Share to',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in convs)
                  ListTile(
                    leading: Avatar(
                        url: c.avatar ?? c.otherUser?.picture,
                        name: _convName(c)),
                    title: Text(_convName(c),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (target == null || !context.mounted) return;
  try {
    await api.messaging
        .send(target.id, MessageCreate(type: 'post', postId: post.id));
    if (context.mounted) showInfo(context, 'Shared to chat');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Promotes a post as a sponsored ad (budget, days, CPC).
Future<void> _promotePost(BuildContext context, Post post) async {
  final result = await showDialog<(int, double, double)>(
    context: context,
    builder: (_) => const _PromoteDialog(),
  );
  if (result == null || !context.mounted) return;
  try {
    await api.ads.promotePost(post.id,
        days: result.$1, budget: result.$2, cpc: result.$3);
    if (context.mounted) showInfo(context, 'Post promoted 🚀');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Long-press the like button to react — including 👎 to dislike (the dislike
/// lives here so like + dislike are one button: tap to like, hold to dislike).
/// Returns the server's updated post so the caller can refresh its state in
/// place (otherwise a 👎/reaction wouldn't visibly change the like button until
/// the next refresh). Null if cancelled or the call failed.
Future<Post?> reactToPost(BuildContext context, Post post) async {
  const emojis = ['👍', '👎', '❤️', '😂', '😮', '😢', '😡', '🔥'];
  final emoji = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final e in emojis)
              InkWell(
                onTap: () => Navigator.pop(context, e),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(e, style: const TextStyle(fontSize: 30)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (emoji == null || !context.mounted) return null;
  try {
    final updated = await api.feed.react(post.id, emoji);
    if (context.mounted) showInfo(context, 'Reacted $emoji');
    return updated;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

Future<void> _reportPost(BuildContext context, Post post) async {
  final controller = TextEditingController();
  final String? reason;
  try {
    reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report post'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'Reason', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  controller.text.trim().isEmpty
                      ? 'inappropriate'
                      : controller.text.trim()),
              child: const Text('Report')),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
  if (reason == null || !context.mounted) return;
  try {
    await api.feed.report(post.id, reason);
    if (context.mounted) showInfo(context, 'Reported. Thank you.');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// A single post row with author, text and engagement actions.
///
/// Tapping the row opens the post's detail/thread. Set [tappable] to false to
/// disable that (e.g. when the row is already inside a detail view).
class PostTile extends StatefulWidget {
  const PostTile(
      {super.key,
      required this.post,
      this.onChanged,
      this.tappable = true,
      this.card = false,
      this.compact = false,
      this.onComment});

  final Post post;

  /// Called after the post is edited/pinned/deleted via the ⋯ menu.
  final VoidCallback? onChanged;
  final bool tappable;

  /// When true, render as a rounded surface card with margin (feed style).
  final bool card;

  /// Overrides the comment button's default action (open the post's detail).
  /// Used by the detail screen itself to focus its reply composer instead.
  final VoidCallback? onComment;

  /// Renders the same post layout at a smaller scale (tighter padding, smaller
  /// avatar, slightly smaller text) — used for replies in a thread.
  final bool compact;

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  // Local, optimistic engagement state so taps update in place without a
  // full list refetch (and survive re-parenting).
  late bool _liked;
  late int _likes;
  late bool _bookmarked;
  late bool _reposted;
  late int _reposts;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PostTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync when the host swaps in a refreshed post.
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.likesCount != widget.post.likesCount ||
        oldWidget.post.bookmarksCount != widget.post.bookmarksCount ||
        oldWidget.post.repostsCount != widget.post.repostsCount) {
      _sync();
    }
  }

  void _sync() {
    _liked = post.likedByMe;
    _likes = post.likesCount;
    _bookmarked = post.bookmarkedByMe;
    _reposted = post.repostedByMe;
    _reposts = post.repostsCount;
  }

  Future<void> _toggle(
      Future<void> Function() apiCall, void Function() optimistic) async {
    setState(optimistic);
    try {
      await apiCall();
    } catch (e) {
      if (!mounted) return;
      setState(_sync); // revert to the server-known state
      showError(context, e);
    }
  }

  void _like() => _toggle(() => api.feed.toggleLike(post.id), () {
        if (_liked) {
          _liked = false;
          _likes--;
        } else {
          _liked = true;
          _likes++;
        }
      });

  void _bookmark() => _toggle(() => api.feed.toggleBookmark(post.id), () {
        _bookmarked = !_bookmarked;
      });

  void _repost() => _toggle(() => api.feed.toggleRepost(post.id), () {
        _reposted = !_reposted;
        _reposts += _reposted ? 1 : -1;
      });

  /// Long-press the repost button: choose a plain repost or a quote.
  Future<void> _repostMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_reposted ? Icons.repeat_on : Icons.repeat),
              title: Text(_reposted ? 'Undo repost' : 'Repost'),
              onTap: () => Navigator.pop(context, 'repost'),
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('Quote'),
              onTap: () => Navigator.pop(context, 'quote'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'repost') {
      _repost();
    } else if (choice == 'quote' && mounted) {
      final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ComposeScreen(quoteOf: post.id, quotedPreview: post),
      ));
      if (posted == true) onChanged?.call();
    }
  }

  VoidCallback? get onChanged => widget.onChanged;
  bool get tappable => widget.tappable;
  bool get card => widget.card;
  bool get compact => widget.compact;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    final content = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16, vertical: compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.promoted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('SPONSORED',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5)),
            ),
          if (post.pinned)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.push_pin, size: 13,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 4),
                Text('Pinned',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 12)),
              ]),
            ),
          Row(
            children: [
              GestureDetector(
                onTap: () => ProfileScreen.open(context, author.userId),
                child: Avatar(
                    url: author.picture,
                    name: author.name,
                    radius: compact ? 16 : 20),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(author.name,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (author.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 16, color: Color(0xFF3B82F6)),
                        ],
                      ],
                    ),
                    if (author.username != null)
                      Text('@${author.username} · ${shortAgo(post.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if ((post.raw['min_sub_tier'] is num) &&
                  (post.raw['min_sub_tier'] as num) > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6C455).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock, size: 11, color: Color(0xFFF6C455)),
                    SizedBox(width: 3),
                    Text('Subscribers',
                        style: TextStyle(
                            color: Color(0xFFF6C455),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              IconButton(
                icon: Icon(Icons.more_horiz,
                    color: Theme.of(context).colorScheme.outline),
                visualDensity: VisualDensity.compact,
                onPressed: () => _showPostMenu(context, post,
                    onChanged: onChanged,
                    bookmarked: _bookmarked,
                    onBookmark: _bookmark),
              ),
            ],
          ),
          if (post.title != null && post.title!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(post.title!,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 16)),
          ],
          if (post.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            LinkedText(post.text),
          ],
          if (post.media.isNotEmpty)
            // Data saver (Customize feed): collapse media to a small tag.
            feedPrefs.showMedia
                ? _MediaPreview(
                    media: post.media.first, extra: post.media.length - 1)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(
                          post.media.first.isVideo
                              ? Icons.videocam_outlined
                              : Icons.image_outlined,
                          size: 15,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                          '${post.media.first.isVideo ? 'Video' : 'Photo'}'
                          '${post.media.length > 1 ? ' +${post.media.length - 1}' : ''}'
                          ' · tap to view',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).colorScheme.outline)),
                    ]),
                  ),
          if (post.quotedPost != null) ...[
            const SizedBox(height: 8),
            _QuotedPost(quoted: post.quotedPost!),
          ],
          if (post.poll != null) ...[
            const SizedBox(height: 8),
            _PostPoll(postId: post.id, poll: post.poll!),
          ],
          const SizedBox(height: 4),
          // Like, comment and repost grouped together on the left; views (if
          // any) sit on the right. Like is a single control — long-press it to
          // pick any reaction (👎 included), so like/dislike are combined.
          Row(
            children: [
              PostAction(
                icon: _liked ? Icons.favorite : Icons.favorite_border,
                count: _likes,
                color: _liked ? OkayColors.danger : null,
                onTap: _like,
                onLongPress: () async {
                  // Reacting (e.g. 👎) switches/clears the like server-side, so
                  // re-sync from the returned post to reflect it immediately.
                  final updated = await reactToPost(context, post);
                  if (updated != null && mounted) {
                    setState(() {
                      _liked = updated.likedByMe;
                      _likes = updated.likesCount;
                      _bookmarked = updated.bookmarkedByMe;
                      _reposted = updated.repostedByMe;
                      _reposts = updated.repostsCount;
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              PostAction(
                icon: Icons.mode_comment_outlined,
                count: post.repliesCount,
                onTap:
                    widget.onComment ?? () => PostDetailScreen.open(context, post),
              ),
              const SizedBox(width: 8),
              PostAction(
                icon: Icons.repeat,
                count: _reposts,
                color: _reposted ? const Color(0xFF22C55E) : null,
                onTap: _repost,
                onLongPress: _repostMenu,
              ),
              if (post.viewsCount > 0) ...[
                const SizedBox(width: 8),
                PostAction(
                    icon: Icons.visibility_outlined, count: post.viewsCount),
              ],
            ],
          ),
          // Thread connector: when the author continued this post as a thread,
          // offer to open the chain. Feed-only — the detail view already shows it.
          if (tappable && post.isThread)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () => PostDetailScreen.open(context, post),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.forum_outlined,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('Show this thread',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );

    Widget result = content;
    // Post text size (Customize feed) plus a slight reduction for compact
    // (reply) tiles, scaled together so all text in the tile shrinks evenly.
    final scale = feedPrefs.textScale * (compact ? 0.9 : 1.0);
    if (scale != 1.0) {
      result = MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: result,
      );
    }
    if (tappable) {
      result = InkWell(
        onTap: () => PostDetailScreen.open(context, post),
        borderRadius: card ? BorderRadius.circular(16) : null,
        child: result,
      );
    }
    if (card) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: result,
      );
    }
    return result;
  }
}

/// An interactive poll: tap an option to vote, then see the results.
class _PostPoll extends StatefulWidget {
  const _PostPoll({required this.postId, required this.poll});

  final String postId;
  final Poll poll;

  @override
  State<_PostPoll> createState() => _PostPollState();
}

class _PostPollState extends State<_PostPoll> {
  late Poll _poll = widget.poll;
  bool _voting = false;

  bool get _locked => _poll.votedOptionId != null || _poll.closed;

  Future<void> _vote(String optionId) async {
    if (_locked || _voting) return;
    setState(() => _voting = true);
    try {
      final updated = await api.feed.votePoll(widget.postId, optionId);
      if (mounted && updated.poll != null) {
        setState(() => _poll = updated.poll!);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _poll.totalVotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final o in _poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: _locked ? null : () => _vote(o.id),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Container(
                      height: 38,
                      color: scheme.surfaceContainerHighest,
                    ),
                    // Result fill bar.
                    if (_locked)
                      FractionallySizedBox(
                        widthFactor: total > 0 ? o.votes / total : 0,
                        child: Container(
                          height: 38,
                          color: o.id == _poll.votedOptionId
                              ? scheme.primary.withValues(alpha: 0.55)
                              : scheme.primary.withValues(alpha: 0.22),
                        ),
                      ),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          if (o.id == _poll.votedOptionId)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.check_circle, size: 16),
                            ),
                          Expanded(
                            child: Text(o.text,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (_locked)
                            Text(
                                '${total > 0 ? ((o.votes / total) * 100).round() : 0}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Text(
          [
            '$total ${total == 1 ? 'vote' : 'votes'}',
            if (_poll.closed) 'final' else 'tap to vote',
          ].join(' · '),
          style: TextStyle(color: scheme.outline, fontSize: 12),
        ),
      ],
    );
  }
}

/// A compact embedded card for a quoted post.
class _QuotedPost extends StatelessWidget {
  const _QuotedPost({required this.quoted});

  final Post quoted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(
                  url: quoted.author.picture,
                  name: quoted.author.name,
                  radius: 11),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  quoted.author.username != null
                      ? '${quoted.author.name} · @${quoted.author.username}'
                      : quoted.author.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          if (quoted.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(quoted.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ],
          if (quoted.media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                      quoted.media.first.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      size: 14,
                      color: scheme.outline),
                  const SizedBox(width: 4),
                  Text(quoted.media.first.isVideo ? 'Video' : 'Photo',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A single icon + formatted count engagement button.
class PostAction extends StatelessWidget {
  const PostAction({
    super.key,
    required this.icon,
    required this.count,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(icon,
                  key: ValueKey('$icon-${color != null}'),
                  size: 18,
                  color: color ?? muted),
            ),
            // Zen mode (Customize feed) hides the counts, icons stay.
            if (count > 0 && !feedPrefs.hideCounts) ...[
              const SizedBox(width: 6),
              Text(formatCount(count),
                  style: TextStyle(color: color ?? muted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.media, this.extra = 0});

  final PostMedia media;

  /// Number of additional media items beyond this one (for a "+N" badge).
  final int extra;

  @override
  Widget build(BuildContext context) {
    final url = media.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              media.isVideo
                  ? PostVideo(url: url)
                  : Image.network(url,
                      fit: BoxFit.cover,
                      // Fade the photo in once decoded instead of popping it
                      // over a black flash.
                      frameBuilder: (_, child, frame, wasSync) {
                        if (wasSync) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest),
                      errorBuilder: (_, __, ___) => ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Icon(Icons.broken_image_outlined,
                              color: Theme.of(context).colorScheme.outline))),
              if (extra > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.collections,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('+$extra',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Budget / duration / CPC input for promoting a post.
class _PromoteDialog extends StatefulWidget {
  const _PromoteDialog();

  @override
  State<_PromoteDialog> createState() => _PromoteDialogState();
}

class _PromoteDialogState extends State<_PromoteDialog> {
  int _days = 7;
  final _budget = TextEditingController(text: '20');
  final _cpc = TextEditingController(text: '0.50');

  @override
  void dispose() {
    _budget.dispose();
    _cpc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Promote post'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Run for'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _days,
                onChanged: (v) => setState(() => _days = v ?? _days),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 day')),
                  DropdownMenuItem(value: 3, child: Text('3 days')),
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 14, child: Text('14 days')),
                  DropdownMenuItem(value: 30, child: Text('30 days')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _budget,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Total budget',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cpc,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Max cost per click',
                prefixIcon: Icon(Icons.ads_click),
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final b = double.tryParse(_budget.text.trim());
            final c = double.tryParse(_cpc.text.trim());
            if (b == null || b <= 0 || c == null || c <= 0) return;
            Navigator.pop(context, (_days, b, c));
          },
          child: const Text('Promote'),
        ),
      ],
    );
  }
}
