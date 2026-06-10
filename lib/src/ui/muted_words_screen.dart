import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Mute keywords (hide matching posts) and prioritize keywords (boost them),
/// mirroring the web app's `/muted-words` (saved via `updateMe`).
class MutedWordsScreen extends StatefulWidget {
  const MutedWordsScreen({super.key});

  @override
  State<MutedWordsScreen> createState() => _MutedWordsScreenState();
}

class _MutedWordsScreenState extends State<MutedWordsScreen> {
  final Future<User> _me = api.auth.me();
  List<String> _muted = [];
  List<String> _priority = [];
  bool _loaded = false;
  bool _saving = false;

  List<String> _wordsFrom(Map<String, dynamic> raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v is List) return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
      if (v is String && v.isNotEmpty) {
        return v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }
    return [];
  }

  void _hydrate(User u) {
    if (_loaded) return;
    _loaded = true;
    _muted = _wordsFrom(u.raw, ['muted_words', 'mutedWords']);
    _priority = _wordsFrom(u.raw, ['priority_words', 'priorityWords', 'boosted_words']);
  }

  Future<void> _add(bool muted) async {
    final word = await promptText(context,
        title: muted ? 'Mute a word' : 'Prioritize a word',
        hint: 'keyword or #hashtag',
        action: 'Add');
    final clean = word?.trim().toLowerCase();
    if (clean == null || clean.isEmpty) return;
    setState(() {
      final list = muted ? _muted : _priority;
      if (!list.contains(clean)) list.add(clean);
    });
    _save();
  }

  void _remove(bool muted, String word) {
    setState(() => (muted ? _muted : _priority).remove(word));
    _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await api.auth.updateProfile({
        'muted_words': _muted,
        'priority_words': _priority,
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, String subtitle, IconData icon, bool muted,
      List<String> words) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: scheme.outline, fontSize: 12.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in words)
                InputChip(
                  label: Text(w),
                  onDeleted: () => _remove(muted, w),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => _add(muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Muted & priority words'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: FutureBuilder<User>(
        future: _me,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return CenteredMessage(
                message: messageFor(snap.error), icon: Icons.error_outline);
          }
          _hydrate(snap.data!);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _section(
                  'Muted words',
                  'Posts containing these are hidden from your feeds.',
                  Icons.volume_off_outlined,
                  true,
                  _muted),
              _section(
                  'Priority words',
                  'Posts with these are boosted higher in your feeds.',
                  Icons.trending_up,
                  false,
                  _priority),
            ],
          );
        },
      ),
    );
  }
}
