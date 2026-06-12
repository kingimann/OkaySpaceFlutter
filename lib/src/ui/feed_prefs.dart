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
  bool _hideReposts = false;
  bool _hideSponsored = false;
  bool _showMedia = true;
  bool _showTrending = true;
  bool _loaded = false;

  /// 'explore' | 'following' — which tab the feed opens on.
  String get defaultTab => _defaultTab;
  bool get hideReposts => _hideReposts;
  bool get hideSponsored => _hideSponsored;

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
          _hideReposts = m['hide_reposts'] == true;
          _hideSponsored = m['hide_sponsored'] == true;
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
    bool? hideReposts,
    bool? hideSponsored,
    bool? showMedia,
    bool? showTrending,
  }) {
    _defaultTab = defaultTab ?? _defaultTab;
    _hideReposts = hideReposts ?? _hideReposts;
    _hideSponsored = hideSponsored ?? _hideSponsored;
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
          'hide_reposts': _hideReposts,
          'hide_sponsored': _hideSponsored,
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
              ValueListenableBuilder<bool>(
                valueListenable: hideStoriesController,
                builder: (context, hidden, _) => SwitchListTile(
                  title: const Text('Show stories'),
                  value: !hidden,
                  onChanged: (v) => hideStoriesController.set(!v),
                ),
              ),
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
