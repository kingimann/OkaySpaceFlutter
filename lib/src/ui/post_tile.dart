import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'linked_text.dart';
import 'post_detail_screen.dart';
import 'post_video.dart';
import 'profile_screen.dart';

/// A single post row with author, text and engagement actions.
///
/// Tapping the row opens the post's detail/thread. Set [tappable] to false to
/// disable that (e.g. when the row is already inside a detail view).
class PostTile extends StatelessWidget {
  const PostTile(
      {super.key,
      required this.post,
      this.onLike,
      this.tappable = true,
      this.card = false});

  final Post post;
  final VoidCallback? onLike;
  final bool tappable;

  /// When true, render as a rounded surface card with margin (feed style).
  final bool card;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                child: Avatar(url: author.picture, name: author.name),
              ),
              const SizedBox(width: 12),
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
                              size: 16, color: Colors.blue),
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
          if (post.media.isNotEmpty) _MediaPreview(media: post.media.first),
          if (post.quotedPost != null) ...[
            const SizedBox(height: 8),
            _QuotedPost(quoted: post.quotedPost!),
          ],
          if (post.poll != null) ...[
            const SizedBox(height: 8),
            _PostPoll(postId: post.id, poll: post.poll!),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PostAction(
                icon: post.likedByMe ? Icons.favorite : Icons.favorite_border,
                count: post.likesCount,
                color: post.likedByMe ? Colors.red : null,
                onTap: onLike,
              ),
              _PostAction(
                  icon: Icons.mode_comment_outlined, count: post.repliesCount),
              _PostAction(icon: Icons.repeat, count: post.repostsCount),
              if (post.viewsCount > 0)
                _PostAction(
                    icon: Icons.visibility_outlined, count: post.viewsCount),
              _PostAction(
                icon: post.bookmarkedByMe
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                count: post.bookmarksCount,
              ),
            ],
          ),
        ],
      ),
    );

    Widget result = content;
    if (tappable) {
      result = InkWell(
        onTap: () => PostDetailScreen.open(context, post),
        child: result,
      );
    }
    if (card) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
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
class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.count,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final int count;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? muted),
            if (count > 0) ...[
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
  const _MediaPreview({required this.media});

  final PostMedia media;

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
          child: media.isVideo
              ? PostVideo(url: url)
              : Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black12)),
        ),
      ),
    );
  }
}
