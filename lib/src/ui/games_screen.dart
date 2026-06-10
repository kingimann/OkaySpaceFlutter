import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Browse and create games with SDK leaderboards (§11 `/games`).
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  late Future<List<Game>> _games = api.games.games();

  Future<void> _reload() async {
    setState(() => _games = api.games.games());
    await _games;
  }

  Future<void> _create() async {
    final title = await promptText(context, title: 'Game title', action: 'Next');
    if (title == null || title.trim().isEmpty) return;
    if (!mounted) return;
    final url = await promptText(context,
        title: 'Game URL', hint: 'https://…', action: 'Create');
    if (url == null || url.trim().isEmpty) return;
    try {
      await api.games.create(title: title.trim(), url: url.trim());
      if (mounted) {
        showInfo(context, 'Game created');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Games'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add game',
            onPressed: _create,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Game>>(
          future: _games,
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
            final games = snap.data ?? const <Game>[];
            if (games.isEmpty) {
              return const CenteredMessage(
                  message: 'No games yet.', icon: Icons.sports_esports_outlined);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: games.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final g = games[i];
                return ListTile(
                  leading: g.thumbnail != null && g.thumbnail!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(g.thumbnail!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.videogame_asset)),
                        )
                      : const CircleAvatar(
                          child: Icon(Icons.sports_esports_outlined)),
                  title: Text(g.title),
                  subtitle: Text([
                    if (g.ownerName != null) 'by ${g.ownerName}',
                    '${g.plays} plays',
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GameDetailScreen(game: g))),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// A game's detail: play link + leaderboard (§11 `/game/[id]`).
class GameDetailScreen extends StatefulWidget {
  const GameDetailScreen({super.key, required this.game});

  final Game game;

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  late Future<List<Map<String, dynamic>>> _board =
      api.games.leaderboard(widget.game.id);

  String get _playUrl => 'https://okayspace.ca/game/${widget.game.id}';

  Future<void> _play() async {
    Clipboard.setData(ClipboardData(text: _playUrl));
    try {
      await api.games.recordPlay(widget.game.id);
    } catch (_) {/* best effort */}
    if (mounted) {
      showInfo(context, 'Play link copied: $_playUrl');
      setState(() => _board = api.games.leaderboard(widget.game.id));
    }
  }

  String _s(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m[k] != null && '${m[k]}'.isNotEmpty) return '${m[k]}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(title: Text(g.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (g.thumbnail != null && g.thumbnail!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(g.thumbnail!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          const SizedBox(height: 12),
          Text(g.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          if (g.ownerName != null)
            Text('by ${g.ownerName} · ${g.plays} plays',
                style: TextStyle(color: scheme.outline)),
          if (g.description != null && g.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(g.description!),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play (copy link)'),
          ),
          const SizedBox(height: 24),
          const Text('Leaderboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _board,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return Text('No scores yet.',
                    style: TextStyle(color: scheme.outline));
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            scheme.primary.withValues(alpha: 0.12),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(_s(rows[i],
                          ['name', 'user_name', 'username', 'player'])),
                      trailing: Text(_s(rows[i], ['score', 'points']),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
