import 'package:flutter/material.dart';

import '../../okayspace_api.dart';

/// A single API instance shared across the demo app.
final OkaySpaceApi api = OkaySpaceApi();

/// Extracts a user-facing message from any error thrown by the client.
String messageFor(Object? error) =>
    error is ApiException ? error.message : '${error ?? 'Something went wrong.'}';

/// Shows a transient error message.
void showError(BuildContext context, Object? error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(messageFor(error))));
}

/// A circular avatar that falls back to the first initial.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, this.name, this.radius = 20});

  final String? url;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = (name != null && name!.isNotEmpty) ? name![0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty)
          ? Text(initial, style: TextStyle(fontSize: radius * 0.8))
          : null,
    );
  }
}

/// A full-screen centered message, optionally with a retry button. Lives in a
/// scrollable so it works inside [RefreshIndicator].
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        children: [
          SizedBox(height: constraints.maxHeight * 0.3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard async-list scaffold: spinner while loading, error+retry on failure,
/// empty message when there's nothing, otherwise [builder].
class AsyncList<T> extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.future,
    required this.builder,
    this.emptyMessage = 'Nothing here yet.',
  });

  final Future<List<T>> future;
  final Widget Function(BuildContext, List<T>) builder;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CenteredMessage(message: messageFor(snapshot.error));
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return CenteredMessage(message: emptyMessage);
        return builder(context, items);
      },
    );
  }
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
