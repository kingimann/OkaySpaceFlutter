import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Compose and publish a new post with optional photo attachments.
/// Returns `true` via [Navigator] when a post was created.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _text = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _posting = false;

  // Poll composer.
  bool _poll = false;
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  Duration _duration = const Duration(days: 1);

  static const _durations = <(String, Duration)>[
    ('1 hour', Duration(hours: 1)),
    ('6 hours', Duration(hours: 6)),
    ('1 day', Duration(days: 1)),
    ('3 days', Duration(days: 3)),
    ('7 days', Duration(days: 7)),
  ];

  @override
  void dispose() {
    _text.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _togglePoll() => setState(() => _poll = !_poll);

  Future<void> _addPhotos() async {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (files.isEmpty) return;
    for (final f in files) {
      _photos.add(await f.readAsBytes());
    }
    if (mounted) setState(() {});
  }

  // Location tag.
  String? _placeName;
  double? _placeLat;
  double? _placeLng;

  // Audience / interaction options.
  String _commentPolicy = 'everyone'; // everyone | followers | none
  bool _likesDisabled = false;
  bool _subscribersOnly = false;

  bool get _canPost =>
      !_posting &&
      (_text.text.trim().isNotEmpty || _photos.isNotEmpty || _poll);

  Future<void> _addLocation() async {
    final query = await promptText(context,
        title: 'Tag a location',
        hint: 'Search a place or address',
        action: 'Search');
    if (query == null) return;
    try {
      final results = await api.roadside.geocode(query);
      if (!mounted) return;
      if (results.isEmpty) {
        showInfo(context, 'No places found.');
        return;
      }
      final r = results.first;
      final lat = r['lat'] ?? r['latitude'];
      final lng = r['lng'] ?? r['lon'] ?? r['longitude'];
      setState(() {
        _placeName = '${r['name'] ?? r['display_name'] ?? query}';
        _placeLat = lat is num ? lat.toDouble() : double.tryParse('$lat');
        _placeLng = lng is num ? lng.toDouble() : double.tryParse('$lng');
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _options2() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                  title: Text('Post options',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              ListTile(
                leading: const Icon(Icons.comment_outlined),
                title: const Text('Who can reply'),
                trailing: DropdownButton<String>(
                  value: _commentPolicy,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                    DropdownMenuItem(
                        value: 'followers', child: Text('Followers')),
                    DropdownMenuItem(value: 'none', child: Text('No one')),
                  ],
                  onChanged: (v) {
                    setSheet(() => setState(() => _commentPolicy = v ?? 'everyone'));
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.favorite_border),
                title: const Text('Hide like counts'),
                value: _likesDisabled,
                onChanged: (v) =>
                    setSheet(() => setState(() => _likesDisabled = v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Subscribers only'),
                value: _subscribersOnly,
                onChanged: (v) =>
                    setSheet(() => setState(() => _subscribersOnly = v)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _post() async {
    setState(() => _posting = true);
    try {
      final media = _photos
          .map((b) => PostMedia(type: 'image', base64: base64Encode(b)))
          .toList();

      PollCreate? poll;
      if (_poll) {
        final opts = _options
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        if (opts.length < 2) {
          showInfo(context, 'Add at least 2 poll options');
          setState(() => _posting = false);
          return;
        }
        poll = PollCreate(
          options: opts.map(PollOptionCreate.new).toList(),
          endsAt: DateTime.now().add(_duration),
        );
      }

      await api.feed.createPost(PostCreate(
        text: _text.text.trim(),
        media: media,
        poll: poll,
        placeName: _placeName,
        placeLatitude: _placeLat,
        placeLongitude: _placeLng,
        commentPolicy: _commentPolicy == 'everyone' ? null : _commentPolicy,
        likesDisabled: _likesDisabled ? true : null,
        minSubTier: _subscribersOnly ? 1 : null,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New post'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: _canPost ? _post : null,
              child: _posting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLines: null,
            minLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: "What's happening?",
              border: InputBorder.none,
              filled: false,
            ),
          ),
          if (_photos.isNotEmpty)
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_photos[i],
                          width: 110, height: 110, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_placeName != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.place, size: 18),
                  label: Text(_placeName!),
                  onDeleted: () => setState(() {
                    _placeName = null;
                    _placeLat = null;
                    _placeLng = null;
                  }),
                ),
              ),
            ),
          if (_poll) _buildPollEditor(context),
        ],
      ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _addPhotos,
                icon: const Icon(Icons.image_outlined),
                tooltip: 'Add photos',
              ),
              IconButton(
                onPressed: _togglePoll,
                icon: const Icon(Icons.poll_outlined),
                tooltip: 'Poll',
                color: _poll ? Theme.of(context).colorScheme.primary : null,
              ),
              IconButton(
                onPressed: _addLocation,
                icon: const Icon(Icons.place_outlined),
                tooltip: 'Tag location',
                color: _placeName != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              const Spacer(),
              IconButton(
                onPressed: _options2,
                icon: const Icon(Icons.tune),
                tooltip: 'Post options',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPollEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Poll', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove poll',
                onPressed: () => setState(() => _poll = false),
              ),
            ],
          ),
          for (var i = 0; i < _options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _options[i],
                      decoration: InputDecoration(
                        hintText: 'Option ${i + 1}',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_options.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () =>
                          setState(() => _options.removeAt(i).dispose()),
                    ),
                ],
              ),
            ),
          if (_options.length < 4)
            TextButton.icon(
              onPressed: () =>
                  setState(() => _options.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Add option'),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: scheme.outline),
              const SizedBox(width: 8),
              const Text('Ends in'),
              const SizedBox(width: 12),
              DropdownButton<Duration>(
                value: _duration,
                onChanged: (d) => setState(() => _duration = d ?? _duration),
                items: [
                  for (final (label, dur) in _durations)
                    DropdownMenuItem(value: dur, child: Text(label)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
