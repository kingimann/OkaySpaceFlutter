import 'package:flutter/material.dart';

import 'common.dart';
import 'profile_screen.dart';

/// The current user's recent activity (likes, follows, mentions and other
/// engagement on their content), backed by `/notifications/activity`.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late Future<List<Map<String, dynamic>>> _items = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await api.notifications.activity();
    final list = data is Map
        ? (data['activity'] ??
            data['items'] ??
            data['events'] ??
            data['data'] ??
            data['results'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> _reload() async {
    setState(() => _items = _load());
    await _items;
  }

  String _s(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return '';
  }

  IconData _iconFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('like') || t.contains('react')) return Icons.favorite;
    if (t.contains('follow')) return Icons.person_add_alt_1;
    if (t.contains('comment') || t.contains('reply')) return Icons.mode_comment;
    if (t.contains('mention')) return Icons.alternate_email;
    if (t.contains('repost') || t.contains('share')) return Icons.repeat;
    if (t.contains('tip') || t.contains('pay')) return Icons.volunteer_activism;
    if (t.contains('friend')) return Icons.handshake;
    return Icons.notifications_none;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Activity')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _items,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const ListSkeleton();
            }
            if (snap.hasError) {
              return CenteredMessage(
                  message: messageFor(snap.error),
                  icon: Icons.error_outline,
                  onRetry: _reload);
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return const CenteredMessage(
                  message: 'No activity yet.', icon: Icons.bolt_outlined);
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: kBottomNavInset),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = items[i];
                final type = _s(m, ['type', 'action', 'event']);
                final actorName =
                    _s(m, ['actor_name', 'actorName', 'name', 'username']);
                final picture =
                    _s(m, ['actor_picture', 'actorPicture', 'picture', 'avatar']);
                final message =
                    _s(m, ['message', 'text', 'body', 'description']);
                final actorId = _s(m, ['actor_id', 'actorId', 'user_id', 'uid']);
                final created = _s(m, ['created_at', 'createdAt', 'time', 'ts']);
                final when = DateTime.tryParse(created);
                final title = actorName.isNotEmpty ? actorName : 'Someone';
                final subtitle =
                    message.isNotEmpty ? message : type.replaceAll('_', ' ');
                return ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Avatar(
                          url: picture.isEmpty ? null : picture,
                          name: title,
                          radius: 22),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: scheme.primary,
                          child: Icon(_iconFor(type),
                              size: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  title: Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(subtitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: when == null
                      ? null
                      : Text(shortAgo(when),
                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                  onTap: actorId.isEmpty
                      ? null
                      : () => ProfileScreen.open(context, actorId),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
