import 'package:flutter/material.dart';

import 'common.dart';
import 'profile_screen.dart';

/// The global activity-points leaderboard (Snapscore-style ranking).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<List<Map<String, dynamic>>> _board;

  @override
  void initState() {
    super.initState();
    _board = api.users.leaderboard();
  }

  Future<void> _reload() async {
    setState(() => _board = api.users.leaderboard());
    await _board;
  }

  String _s(Map<String, dynamic> m, List<String> keys, [String fb = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return fb;
  }

  int _points(Map<String, dynamic> m) {
    final v = m['points'] ?? m['score'] ?? m['activity_points'];
    return v is num ? v.toInt() : 0;
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFF59E0B); // gold
      case 2:
        return const Color(0xFF9CA3AF); // silver
      case 3:
        return const Color(0xFFB45309); // bronze
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Leaderboard')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _board,
            loading: const ListSkeleton(),
            emptyMessage: 'No rankings yet.',
            emptyIcon: Icons.leaderboard_outlined,
            builder: (context, items) => ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, i) {
                final m = items[i];
                final rank = i + 1;
                final name = _s(m, ['name', 'username'], 'User');
                final userId = _s(m, ['user_id', 'id']);
                final level = _s(m, ['level_title', 'level']);
                final medal = _rankColor(rank);
                return ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 28,
                        child: medal != Colors.transparent
                            ? Icon(Icons.emoji_events, color: medal, size: 22)
                            : Text('$rank',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: scheme.outline,
                                    fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 4),
                      Avatar(url: _s(m, ['picture']), name: name, radius: 18),
                    ],
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: level.isNotEmpty ? Text(level) : null,
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(formatCount(_points(m)),
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  onTap: userId.isEmpty
                      ? null
                      : () => ProfileScreen.open(context, userId),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
