import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

/// The user's notifications, with mark-all-read and per-item dismiss.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _notifications;
  late Future<List<Map<String, dynamic>>> _activity;

  @override
  void initState() {
    super.initState();
    _notifications = api.notifications.list();
    _activity = api.notifications.activity().then((d) {
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    });
  }

  Future<void> _reload() async {
    setState(() => _notifications = api.notifications.list());
    await _notifications;
  }

  Future<void> _markAllRead() async {
    try {
      await api.notifications.markAllRead();
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Marks read and navigates to whatever the notification points at:
  /// the related post, otherwise the actor's profile.
  Future<void> _open(AppNotification n) async {
    api.notifications.markRead(n.id).then((_) {
      if (mounted) _reload();
    }).catchError((_) {});

    if (n.postId != null) {
      try {
        final post = await api.feed.getPost(n.postId!);
        if (mounted) PostDetailScreen.open(context, post);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } else if (n.actorId != null) {
      if (mounted) ProfileScreen.open(context, n.actorId!);
    }
  }

  IconData _iconFor(String type) {
    if (type.contains('like')) return Icons.favorite;
    if (type.contains('follow')) return Icons.person_add;
    if (type.contains('comment') || type.contains('reply')) {
      return Icons.mode_comment;
    }
    if (type.contains('message')) return Icons.chat_bubble;
    if (type.contains('mention')) return Icons.alternate_email;
    return Icons.notifications;
  }

  /// A distinct badge color per notification kind, so the list scans quickly.
  Color _colorFor(String type, BuildContext context) {
    if (type.contains('like')) return const Color(0xFFF43F5E); // rosé
    if (type.contains('follow')) return const Color(0xFF10B981); // emerald
    if (type.contains('comment') || type.contains('reply')) {
      return const Color(0xFF06B6D4); // ocean
    }
    if (type.contains('message')) return const Color(0xFF6366F1); // midnight
    if (type.contains('mention')) return const Color(0xFFF97316); // sunset
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: OkayAppBar(
          title: const Text('Notifications'),
          actions: [
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'All'), Tab(text: 'Activity')]),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [_buildNotifications(), _buildActivity()],
          ),
        ),
      ),
    );
  }

  Widget _buildActivity() {
    return AsyncList<Map<String, dynamic>>(
      future: _activity,
      emptyMessage: 'No recent activity.',
      emptyIcon: Icons.bolt_outlined,
      builder: (context, items) => ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final a = items[i];
          final text = '${a['message'] ?? a['text'] ?? a['type'] ?? 'Activity'}';
          final actor = '${a['actor_name'] ?? a['user_name'] ?? ''}';
          return ListTile(
            leading: Avatar(
                url: '${a['actor_picture'] ?? a['picture'] ?? ''}',
                name: actor.isEmpty ? '?' : actor),
            title: Text(actor.isEmpty ? text : '$actor $text'),
          );
        },
      ),
    );
  }

  Widget _buildNotifications() {
    return RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<AppNotification>(
          future: _notifications,
          emptyMessage: "You're all caught up.",
          emptyIcon: Icons.check_circle_outline,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              final text = n.message ??
                  '${n.actorName ?? 'Someone'} ${n.type.replaceAll('_', ' ')}';
              final badge = _colorFor(n.type, context);
              return Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) =>
                    api.notifications.dismiss(n.id).catchError((_) {}),
                child: ListTile(
                  // Unread rows get a faint accent wash so they stand out.
                  tileColor: n.read
                      ? null
                      : Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.06),
                  leading: Stack(
                    children: [
                      Avatar(url: n.actorPicture, name: n.actorName),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                width: 1.5),
                          ),
                          child: CircleAvatar(
                            radius: 9,
                            backgroundColor: badge,
                            child: Icon(_iconFor(n.type),
                                size: 11, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(text,
                      style: TextStyle(
                          fontWeight:
                              n.read ? FontWeight.normal : FontWeight.w600)),
                  subtitle: Text(shortAgo(n.createdAt)),
                  trailing: n.read
                      ? null
                      : Icon(Icons.circle, size: 10, color: badge),
                  onTap: () => _open(n),
                ),
              );
            },
          ),
        ),
      );
  }
}
