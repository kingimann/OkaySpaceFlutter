import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'profile_screen.dart';

/// A single post row with author, text and engagement actions.
class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.post, this.onLike});

  final Post post;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return Padding(
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
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: onLike,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  post.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: post.likedByMe ? Colors.red : null,
                ),
              ),
              Text('${post.likesCount}'),
              const SizedBox(width: 20),
              const Icon(Icons.mode_comment_outlined, size: 18),
              const SizedBox(width: 6),
              Text('${post.repliesCount}'),
              const SizedBox(width: 20),
              const Icon(Icons.repeat, size: 18),
              const SizedBox(width: 6),
              Text('${post.repostsCount}'),
            ],
          ),
        ],
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
