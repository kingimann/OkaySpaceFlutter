import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'profile_screen.dart';

/// Bottom sheets that surface who engaged with a post (likers / reposters)
/// and, for the author, the post's insights (analytics + recent viewers).
///
/// All read-only — they only fetch and display.

/// Opens a sheet listing the users from [loader] (e.g. likers / reposters).
/// Tapping a row opens that user's profile.
Future<void> showUserListSheet(
  BuildContext context, {
  required String title,
  required Future<List<PublicUser>> Function() loader,
  String emptyMessage = 'No one yet.',
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (context, scrollController) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: _UserList(
              controller: scrollController,
              loader: loader,
              emptyMessage: emptyMessage,
            ),
          ),
        ],
      ),
    ),
  );
}

class _UserList extends StatefulWidget {
  const _UserList({
    required this.controller,
    required this.loader,
    required this.emptyMessage,
  });

  final ScrollController controller;
  final Future<List<PublicUser>> Function() loader;
  final String emptyMessage;

  @override
  State<_UserList> createState() => _UserListState();
}

class _UserListState extends State<_UserList> {
  late Future<List<PublicUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PublicUser>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CenteredMessage(
              message: messageFor(snapshot.error), icon: Icons.error_outline);
        }
        final users = snapshot.data ?? const [];
        if (users.isEmpty) {
          return CenteredMessage(
              message: widget.emptyMessage, icon: Icons.people_outline);
        }
        return ListView.builder(
          controller: widget.controller,
          itemCount: users.length,
          itemBuilder: (context, i) {
            final u = users[i];
            return UserRowTile(user: u);
          },
        );
      },
    );
  }
}

/// A single tappable user row (avatar + name + handle), opening their profile.
class UserRowTile extends StatelessWidget {
  const UserRowTile({super.key, required this.user});

  final PublicUser user;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Avatar(url: user.picture, name: user.name),
      title: Row(
        children: [
          Flexible(
            child: Text(user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (user.verified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 15, color: Colors.blue),
          ],
        ],
      ),
      subtitle: user.username != null
          ? Text('@${user.username}',
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onTap: () {
        Navigator.pop(context);
        ProfileScreen.open(context, user.userId);
      },
    );
  }
}

/// Opens a read-only "insights" sheet for the post [postId]: analytics numbers
/// plus the recent viewers list. Intended for the post author only.
Future<void> showPostInsightsSheet(BuildContext context, String postId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) =>
          _Insights(postId: postId, controller: scrollController),
    ),
  );
}

class _Insights extends StatefulWidget {
  const _Insights({required this.postId, required this.controller});

  final String postId;
  final ScrollController controller;

  @override
  State<_Insights> createState() => _InsightsState();
}

class _InsightsState extends State<_Insights> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => Future.wait([
        api.feed.postAnalytics(widget.postId),
        api.feed.viewers(widget.postId),
      ]);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CenteredMessage(
              message: messageFor(snapshot.error), icon: Icons.error_outline);
        }
        final data = snapshot.data!;
        final analytics = data[0];
        final viewers = data[1];
        return _InsightsBody(
          analytics: analytics,
          viewers: viewers,
          controller: widget.controller,
        );
      },
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({
    required this.analytics,
    required this.viewers,
    required this.controller,
  });

  final Map<String, dynamic> analytics;
  final Map<String, dynamic> viewers;
  final ScrollController controller;

  int _int(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  double _double(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  String _engagementRate() {
    final r = _double(analytics, 'engagement_rate');
    // Backends often express this as a 0..1 fraction; scale to a percentage.
    final pct = r <= 1 ? r * 100 : r;
    return '${pct.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewerList =
        (viewers['viewers'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];

    final metrics = <_Metric>[
      _Metric('Impressions', formatCount(_int(analytics, 'impressions'))),
      _Metric(
          'Unique viewers', formatCount(_int(analytics, 'unique_viewers'))),
      _Metric('Engagement rate', _engagementRate()),
      _Metric('Reactions', formatCount(_int(analytics, 'reactions_total'))),
      _Metric('Comments', formatCount(_int(analytics, 'comments'))),
      _Metric('Reposts', formatCount(_int(analytics, 'reposts'))),
      _Metric('Quotes', formatCount(_int(analytics, 'quotes'))),
      _Metric('Bookmarks', formatCount(_int(analytics, 'bookmarks'))),
    ];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Post insights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.6,
              children: [for (final m in metrics) _MetricTile(metric: m)],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Recent viewers',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface)),
        const SizedBox(height: 4),
        if (viewerList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No viewers yet.',
                  style: TextStyle(color: scheme.outline)),
            ),
          )
        else
          for (final v in viewerList)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(
                  url: v['picture'] as String?, name: v['name'] as String?),
              title: Row(
                children: [
                  Flexible(
                    child: Text('${v['name'] ?? 'Someone'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (v['verified'] == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 15, color: Colors.blue),
                  ],
                ],
              ),
              subtitle: v['username'] != null
                  ? Text('@${v['username']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : null,
              onTap: v['user_id'] == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      ProfileScreen.open(context, '${v['user_id']}');
                    },
            ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric.value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(metric.label,
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ],
      ),
    );
  }
}
