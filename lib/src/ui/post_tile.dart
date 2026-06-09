import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

/// A single post row with author, text and engagement actions.
///
/// Tapping the row opens the post's detail/thread. Set [tappable] to false to
/// disable that (e.g. when the row is already inside a detail view).
class PostTile extends StatelessWidget {
  const PostTile(
      {super.key, required this.post, this.onLike, this.tappable = true});

  final Post post;
  final VoidCallback? onLike;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            Text(post.text),
          ],
          if (post.media.isNotEmpty) _MediaPreview(media: post.media.first),
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

    if (!tappable) return content;
    return InkWell(
      onTap: () => PostDetailScreen.open(context, post),
      child: content,
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
              ? Container(
                  color: Colors.black12,
                  child: const Center(child: Icon(Icons.play_circle, size: 48)),
                )
              : Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black12)),
        ),
      ),
    );
  }
}
