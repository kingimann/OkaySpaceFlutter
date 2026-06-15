import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'common.dart';
import 'muted_words_screen.dart';

/// Per-user newsfeed preferences, kept on-device: starting tab, what to hide
/// (reposts / sponsored posts / media previews), and the trending strip.
/// The feed and post tiles listen and re-filter live.
class FeedPrefs extends ChangeNotifier {
  FeedPrefs._() {
    _load();
  }

  static final FeedPrefs instance = FeedPrefs._();

  static const _key = 'okayspace.feed_prefs';
  static const _storage = FlutterSecureStorage();

  String _defaultTab = 'explore';
  String _sort = 'recent';
  final List<({String id, String name})> _mutedAuthors = [];
  bool _hideReposts = false;
  bool _hideSponsored = false;
  bool _hidePolls = false;
  bool _hideCounts = false;
  bool _compact = false;
  String _textSize = 'm';
  bool _showMedia = true;
  bool _showTrending = true;
  bool _loaded = false;

  /// 'explore' | 'following' — which tab the feed opens on.
  String get defaultTab => _defaultTab;

  /// 'recent' | 'top' — how the feed is ordered.
  String get sort => _sort;

  /// People muted from the feed (on-device).
  List<({String id, String name})> get mutedAuthors =>
      List.unmodifiable(_mutedAuthors);
  bool isAuthorMuted(String userId) =>
      _mutedAuthors.any((a) => a.id == userId);

  void muteAuthor(String userId, String name) {
    if (userId.isEmpty || isAuthorMuted(userId)) return;
    _mutedAuthors.add((id: userId, name: name));
    notifyListeners();
    _persist();
  }

  void unmuteAuthor(String userId) {
    _mutedAuthors.removeWhere((a) => a.id == userId);
    notifyListeners();
    _persist();
  }
  bool get hideReposts => _hideReposts;
  bool get hideSponsored => _hideSponsored;
  bool get hidePolls => _hidePolls;

  /// Zen mode: action icons only, no like/repost/reply counts.
  bool get hideCounts => _hideCounts;

  /// Compact layout (flat rows) instead of cards.
  bool get compact => _compact;

  /// 's' | 'm' | 'l' post text size, as a text scale factor.
  String get textSize => _textSize;
  double get textScale => switch (_textSize) {
        's' => 0.9,
        'l' => 1.15,
        _ => 1.0,
      };

  /// False = data saver: media previews collapse to a small chip.
  bool get showMedia => _showMedia;
  bool get showTrending => _showTrending;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw);
        if (m is Map) {
          _defaultTab = m['tab'] == 'following' ? 'following' : 'explore';
          _sort = m['sort'] == 'top' ? 'top' : 'recent';
          final muted = m['muted_authors'];
          if (muted is List) {
            for (final e in muted) {
              if (e is Map && e['id'] is String) {
                _mutedAuthors
                    .add((id: e['id'] as String, name: '${e['name'] ?? ''}'));
              }
            }
          }
          _hideReposts = m['hide_reposts'] == true;
          _hideSponsored = m['hide_sponsored'] == true;
          _hidePolls = m['hide_polls'] == true;
          _hideCounts = m['hide_counts'] == true;
          _compact = m['compact'] == true;
          _textSize = ['s', 'l'].contains(m['text_size'])
              ? m['text_size'] as String
              : 'm';
          _showMedia = m['show_media'] != false;
          _showTrending = m['show_trending'] != false;
        }
      }
    } catch (_) {/* defaults */}
    _loaded = true;
    notifyListeners();
  }

  void update({
    String? defaultTab,
    String? sort,
    bool? hideReposts,
    bool? hideSponsored,
    bool? hidePolls,
    bool? hideCounts,
    bool? compact,
    String? textSize,
    bool? showMedia,
    bool? showTrending,
  }) {
    _defaultTab = defaultTab ?? _defaultTab;
    _sort = sort ?? _sort;
    _hideReposts = hideReposts ?? _hideReposts;
    _hideSponsored = hideSponsored ?? _hideSponsored;
    _hidePolls = hidePolls ?? _hidePolls;
    _hideCounts = hideCounts ?? _hideCounts;
    _compact = compact ?? _compact;
    _textSize = textSize ?? _textSize;
    _showMedia = showMedia ?? _showMedia;
    _showTrending = showTrending ?? _showTrending;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'tab': _defaultTab,
          'sort': _sort,
          'muted_authors': [
            for (final a in _mutedAuthors) {'id': a.id, 'name': a.name},
          ],
          'hide_reposts': _hideReposts,
          'hide_sponsored': _hideSponsored,
          'hide_polls': _hidePolls,
          'hide_counts': _hideCounts,
          'compact': _compact,
          'text_size': _textSize,
          'show_media': _showMedia,
          'show_trending': _showTrending,
        }),
      );
    } catch (_) {/* best effort */}
  }
}

/// Convenience accessor.
final feedPrefs = FeedPrefs.instance;

/// Customize feed: everything that shapes the newsfeed in one place.
class FeedPrefsScreen extends StatelessWidget {
  const FeedPrefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Customize feed')),
      body: MaxWidth(
        child: AnimatedBuilder(
          animation: feedPrefs,
          builder: (context, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('OPEN THE FEED ON',
                    style: TextStyle(
                        color: scheme.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final (id, label) in const [
                      ('explore', 'Explore'),
                      ('following', 'Following')
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: feedPrefs.defaultTab == id,
                          onSelected: (_) =>
                              feedPrefs.update(defaultTab: id),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('SORT BY',
                    style: TextStyle(
                        color: scheme.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final (id, label) in const [
                      ('recent', 'Most recent'),
                      ('top', 'Top engagement')
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: feedPrefs.sort == id,
                          onSelected: (_) => feedPrefs.update(sort: id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Hide reposts'),
                subtitle: const Text('Only original posts and quotes'),
                value: feedPrefs.hideReposts,
                onChanged: (v) => feedPrefs.update(hideReposts: v),
              ),
              SwitchListTile(
                title: const Text('Hide sponsored posts'),
                subtitle: const Text('No promoted content in your feed'),
                value: feedPrefs.hideSponsored,
                onChanged: (v) => feedPrefs.update(hideSponsored: v),
              ),
              SwitchListTile(
                title: const Text('Hide polls'),
                value: feedPrefs.hidePolls,
                onChanged: (v) => feedPrefs.update(hidePolls: v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('APPEARANCE',
                    style: TextStyle(
                        color: scheme.outline,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final (id, label) in const [
                      (false, 'Cards'),
                      (true, 'Compact')
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: feedPrefs.compact == id,
                          onSelected: (_) => feedPrefs.update(compact: id),
                        ),
                      ),
                    const Spacer(),
                    for (final (id, label) in const [
                      ('s', 'A'),
                      ('m', 'A'),
                      ('l', 'A')
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(label,
                              style: TextStyle(
                                  fontSize: switch (id) {
                                's' => 12.0,
                                'l' => 18.0,
                                _ => 15.0
                              })),
                          selected: feedPrefs.textSize == id,
                          onSelected: (_) => feedPrefs.update(textSize: id),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                title: const Text('Zen mode'),
                subtitle:
                    const Text('Hide like, repost & reply counts on posts'),
                value: feedPrefs.hideCounts,
                onChanged: (v) => feedPrefs.update(hideCounts: v),
              ),
              SwitchListTile(
                title: const Text('Show media previews'),
                subtitle: const Text(
                    'Turn off to save data — photos and videos collapse to a tag'),
                value: feedPrefs.showMedia,
                onChanged: (v) => feedPrefs.update(showMedia: v),
              ),
              SwitchListTile(
                title: const Text('Show trending hashtags'),
                value: feedPrefs.showTrending,
                onChanged: (v) => feedPrefs.update(showTrending: v),
              ),
              if (feedPrefs.mutedAuthors.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text('MUTED PEOPLE',
                      style: TextStyle(
                          color: scheme.outline,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in feedPrefs.mutedAuthors)
                        InputChip(
                          label: Text(a.name.isEmpty ? 'User' : a.name),
                          onDeleted: () => feedPrefs.unmuteAuthor(a.id),
                          deleteIcon: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const Divider(),
              ListTile(
                leading: Icon(Icons.volume_off_outlined,
                    color: scheme.primary),
                title: const Text('Muted words'),
                subtitle:
                    const Text('Hide posts containing words you choose'),
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MutedWordsScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
