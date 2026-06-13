import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Star ratings + notes left by users for a real-world place, keyed by a
/// stable [placeKey] so everyone sees the same shared list.
class PlaceReviewsScreen extends StatefulWidget {
  const PlaceReviewsScreen({
    super.key,
    required this.placeKey,
    required this.placeName,
    this.latitude,
    this.longitude,
  });

  final String placeKey;
  final String placeName;
  final double? latitude;
  final double? longitude;

  @override
  State<PlaceReviewsScreen> createState() => _PlaceReviewsScreenState();
}

class _PlaceReviewsScreenState extends State<PlaceReviewsScreen> {
  late Future<List<PlaceReview>> _reviews;
  late Future<ReviewSummary> _summary;

  @override
  void initState() {
    super.initState();
    _reviews = api.guides.placeReviews(widget.placeKey);
    _summary = api.guides.placeReviewSummary(widget.placeKey);
  }

  Future<void> _reload() async {
    setState(() {
      _reviews = api.guides.placeReviews(widget.placeKey);
      _summary = api.guides.placeReviewSummary(widget.placeKey);
    });
    await _reviews;
  }

  Future<void> _delete(PlaceReview r) async {
    try {
      await api.guides.deleteReview(r.id);
      if (!mounted) return;
      showInfo(context, 'Review removed');
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _writeReview() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewComposer(
        placeKey: widget.placeKey,
        placeName: widget.placeName,
        latitude: widget.latitude,
        longitude: widget.longitude,
      ),
    );
    if (added == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Reviews')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _writeReview,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Write a review'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<PlaceReview>>(
            future: _reviews,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const ListSkeleton();
              }
              if (snapshot.hasError) {
                return CenteredMessage(
                  message: messageFor(snapshot.error),
                  icon: Icons.error_outline,
                  onRetry: _reload,
                );
              }
              final reviews = snapshot.data ?? const <PlaceReview>[];
              if (reviews.isEmpty) {
                return CenteredMessage(
                  message: 'No reviews yet.\nBe the first to review '
                      '${widget.placeName}.',
                  icon: Icons.star_outline,
                );
              }
              final average =
                  reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                      reviews.length;
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: kBottomNavInset + 72),
                itemCount: reviews.length + 1,
                separatorBuilder: (_, i) =>
                    i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _Header(
                      placeName: widget.placeName,
                      fallbackAverage: average,
                      fallbackCount: reviews.length,
                      summary: _summary,
                    );
                  }
                  return _ReviewTile(
                    review: reviews[i - 1],
                    onDelete: () => _delete(reviews[i - 1]),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A row of five star icons, filled up to [rating] (supports half stars when
/// [allowHalf] and a fractional value).
class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 18, this.allowHalf = false});

  final double rating;
  final double size;
  final bool allowHalf;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (allowHalf && rating >= i - 0.5)
                    ? Icons.star_half
                    : Icons.star_border,
            size: size,
            color: color,
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.placeName,
    required this.fallbackAverage,
    required this.fallbackCount,
    required this.summary,
  });

  final String placeName;

  /// Shown while the (more accurate) server summary loads or if it fails.
  final double fallbackAverage;
  final int fallbackCount;
  final Future<ReviewSummary> summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: FutureBuilder<ReviewSummary>(
        future: summary,
        builder: (context, snapshot) {
          final s = snapshot.data;
          final average = s?.average ?? fallbackAverage;
          final count = s?.count ?? fallbackCount;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(placeName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(average.toStringAsFixed(1),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 22)),
                  const SizedBox(width: 8),
                  _Stars(rating: average, size: 20, allowHalf: true),
                  const SizedBox(width: 8),
                  Text(
                    count == 1 ? '1 review' : '$count reviews',
                    style: TextStyle(color: scheme.outline),
                  ),
                ],
              ),
              // Rating breakdown bars (5★ → 1★), once the summary lands.
              if (s != null && s.count > 0) ...[
                const SizedBox(height: 12),
                for (var star = 5; star >= 1; star--)
                  _RatingBar(
                    star: star,
                    count: s.distribution[star] ?? 0,
                    total: s.count,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One row of the rating histogram: "5 ★ ▓▓▓▓░ 12".
class _RatingBar extends StatelessWidget {
  const _RatingBar(
      {required this.star, required this.count, required this.total});

  final int star;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text('$star',
                textAlign: TextAlign.right,
                style: TextStyle(color: scheme.outline, fontSize: 12)),
          ),
          const SizedBox(width: 2),
          Icon(Icons.star, size: 12, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: TextStyle(color: scheme.outline, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, required this.onDelete});

  final PlaceReview review;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMine = review.userId == currentUserId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(url: review.userPicture, name: review.userName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(review.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(shortAgo(review.createdAt),
                        style:
                            TextStyle(color: scheme.outline, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                _Stars(rating: review.rating.toDouble()),
                if (review.text != null && review.text!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(review.text!, style: const TextStyle(height: 1.3)),
                ],
              ],
            ),
          ),
          if (isMine)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet composer: a tappable 1–5 star selector and an optional note.
/// Pops `true` once the review has been added.
class _ReviewComposer extends StatefulWidget {
  const _ReviewComposer({
    required this.placeKey,
    required this.placeName,
    this.latitude,
    this.longitude,
  });

  final String placeKey;
  final String placeName;
  final double? latitude;
  final double? longitude;

  @override
  State<_ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<_ReviewComposer> {
  final _text = TextEditingController();
  int _rating = 0;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      showInfo(context, 'Please choose a rating');
      return;
    }
    setState(() => _busy = true);
    try {
      final text = _text.text.trim();
      await api.guides.addReview(
        placeKey: widget.placeKey,
        placeName: widget.placeName,
        rating: _rating,
        latitude: widget.latitude,
        longitude: widget.longitude,
        text: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review ${widget.placeName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 36,
                  onPressed: _busy ? null : () => setState(() => _rating = i),
                  icon: Icon(
                    _rating >= i ? Icons.star : Icons.star_border,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            enabled: !_busy,
            maxLines: 4,
            minLines: 3,
            decoration: const InputDecoration(
              hintText: 'Share details of your experience (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post review'),
            ),
          ),
        ],
      ),
    );
  }
}
