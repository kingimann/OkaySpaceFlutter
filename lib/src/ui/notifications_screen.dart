import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// The user's notifications, with mark-all-read and per-item dismiss.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = api.notifications.list();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<AppNotification>(
          future: _notifications,
          emptyMessage: "You're all caught up.",
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              final text = n.message ??
                  '${n.actorName ?? 'Someone'} ${n.type.replaceAll('_', ' ')}';
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
                  leading: Stack(
                    children: [
                      Avatar(url: n.actorPicture, name: n.actorName),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Icon(_iconFor(n.type),
                              size: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  title: Text(text),
                  subtitle: Text(shortAgo(n.createdAt)),
                  trailing: n.read
                      ? null
                      : Icon(Icons.circle,
                          size: 10,
                          color: Theme.of(context).colorScheme.primary),
                  onTap: () => api.notifications.markRead(n.id).catchError((_) {}),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
