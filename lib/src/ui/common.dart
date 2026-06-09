import 'package:flutter/material.dart';

import '../../okayspace_api.dart';

/// A single API instance shared across the demo app.
final OkaySpaceApi api = OkaySpaceApi();

/// Extracts a user-facing message from any error thrown by the client.
String messageFor(Object? error) =>
    error is ApiException ? error.message : '${error ?? 'Something went wrong.'}';

/// Shows a transient error message as a floating snackbar.
void showError(BuildContext context, Object? error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(messageFor(error)),
    behavior: SnackBarBehavior.floating,
  ));
}

/// Shows a brief confirmation snackbar.
void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
  ));
}

/// Compact count formatter: 1200 → "1.2k", 3_400_000 → "3.4M".
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v < 10 && n % 1000 >= 100 ? 1 : 0)}k';
  }
  final v = n / 1000000;
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)}M';
}

/// Compact relative-time formatter (e.g. "3m", "2h", "5d").
String shortAgo(DateTime time) {
  final d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

/// A circular avatar that falls back to a colored initial.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, this.name, this.radius = 20});

  final String? url;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasName = name != null && name!.isNotEmpty;
    final initial = hasName ? name![0].toUpperCase() : '?';
    // Deterministic tint per name so avatars are distinguishable.
    final hue = hasName ? (name!.codeUnitAt(0) * 47) % 360 : 200;
    final bg = HSLColor.fromAHSL(1, hue.toDouble(), 0.5, 0.6).toColor();
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty)
          ? Text(initial,
              style: TextStyle(
                  fontSize: radius * 0.8,
                  color: Colors.white,
                  fontWeight: FontWeight.w600))
          : null,
    );
  }
}

/// A friendly empty/error state with an icon, message and optional retry.
/// Lives in a scrollable so it works inside [RefreshIndicator].
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({
    super.key,
    required this.message,
    this.icon,
    this.onRetry,
  });

  final String message;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        children: [
          SizedBox(height: constraints.maxHeight * 0.22),
          Icon(icon ?? Icons.inbox_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted)),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A softly-pulsing placeholder box used to build loading skeletons.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_c),
      child: Container(
        width: widget.shape == BoxShape.circle ? widget.height : widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.rectangle
              ? BorderRadius.circular(widget.radius)
              : null,
        ),
      ),
    );
  }
}

/// A list of skeleton "post" rows shown while a feed loads.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(height: 40, shape: BoxShape.circle),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 120, height: 12),
                  SizedBox(height: 8),
                  Skeleton(height: 12),
                  SizedBox(height: 6),
                  Skeleton(width: 200, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standard async-list scaffold: a [loading] placeholder while loading, an
/// error+retry state on failure, an [emptyMessage] when empty, else [builder].
class AsyncList<T> extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.future,
    required this.builder,
    this.emptyMessage = 'Nothing here yet.',
    this.emptyIcon,
    this.loading,
  });

  final Future<List<T>> future;
  final Widget Function(BuildContext, List<T>) builder;
  final String emptyMessage;
  final IconData? emptyIcon;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loading ?? const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CenteredMessage(
              message: messageFor(snapshot.error),
              icon: Icons.error_outline);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return CenteredMessage(message: emptyMessage, icon: emptyIcon);
        }
        return builder(context, items);
      },
    );
  }
}
