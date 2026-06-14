import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import '../core/mapbox_api.dart';
import '../core/cloudinary_api.dart';
import 'common.dart';

/// Compose and publish a new post with optional photo attachments.
/// Returns `true` via [Navigator] when a post was created.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, this.quoteOf, this.quotedPreview});

  /// When set, the new post quotes this post id (with [quotedPreview] shown).
  final String? quoteOf;
  final Post? quotedPreview;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _text = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _posting = false;

  static const _draftKey = 'okayspace.compose_draft';
  final _storage = const FlutterSecureStorage();
  Timer? _draftTimer;

  // @mention autocomplete.
  List<PublicUser> _mentions = const [];
  Timer? _mentionTimer;

  // Thread composer: extra continuation posts published as replies to the
  // first one, so a multi-part thought goes up as a single thread.
  final List<TextEditingController> _threadParts = [];

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
  void initState() {
    super.initState();
    _text.addListener(_saveDraft);
    _loadDraft();
  }

  Widget _quotedPreview(Post p) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(url: p.author.picture, name: p.author.name, radius: 12),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                    p.author.username != null
                        ? '${p.author.name} · @${p.author.username}'
                        : p.author.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          if (p.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Future<void> _loadDraft() async {
    try {
      final d = await _storage.read(key: _draftKey);
      if (d != null && d.isNotEmpty && mounted && _text.text.isEmpty) {
        _text.text = d;
        setState(() {});
        showInfo(context, 'Draft restored');
      }
    } catch (_) {/* ignore */}
  }

  /// Debounced auto-save of the post text (cleared when empty).
  void _saveDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () {
      final t = _text.text;
      if (t.trim().isEmpty) {
        _storage.delete(key: _draftKey).ignore();
      } else {
        _storage.write(key: _draftKey, value: t).ignore();
      }
    });
  }

  void _clearDraft() {
    _draftTimer?.cancel();
    _storage.delete(key: _draftKey).ignore();
  }

  // --- Saved drafts (multiple, user-managed) -------------------------------
  // Stored on the server (api.feed.*Draft). When a server call fails
  // (offline / unauthenticated) we transparently fall back to the local
  // secure-storage copy below so the feature keeps working.

  /// Snapshot of the composer to persist as a draft payload. Mirror any other
  /// composer state here if drafts should remember it.
  Map<String, dynamic> _composerSnapshot(String text) => {'text': text};

  /// Normalized in-memory view of a draft, regardless of its source.
  static _Draft _serverDraft(Map<String, dynamic> d) {
    final payload = d['payload'];
    final text = payload is Map ? '${payload['text'] ?? ''}' : '';
    final stamp = '${d['updated_at'] ?? d['created_at'] ?? ''}';
    return _Draft(
      id: '${d['id']}',
      text: text,
      time: DateTime.tryParse(stamp),
      local: false,
    );
  }

  // -- Local fallback store (legacy `{'t': text, 'at': ms}` shape) -----------
  static const _draftsKey = 'okayspace.post_drafts';

  Future<List<Map<String, dynamic>>> _readLocalDrafts() async {
    try {
      final raw = await _storage.read(key: _draftsKey);
      final list = raw == null ? null : jsonDecode(raw);
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _writeLocalDrafts(List<Map<String, dynamic>> drafts) async {
    try {
      await _storage.write(
          key: _draftsKey, value: jsonEncode(drafts.take(20).toList()));
    } catch (_) {/* best effort */}
  }

  /// Saves the current composer to the server, falling back to local storage.
  Future<void> _saveAsDraft() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    try {
      await api.feed.saveDraft(_composerSnapshot(t));
    } catch (_) {
      final drafts = await _readLocalDrafts();
      drafts.insert(0, {'t': t, 'at': DateTime.now().millisecondsSinceEpoch});
      await _writeLocalDrafts(drafts);
    }
    if (mounted) {
      _text.clear();
      _clearDraft();
      setState(() {});
      showInfo(context, 'Saved to drafts');
    }
  }

  /// Loads drafts from the server; on failure falls back to local storage
  /// (the returned drafts are flagged `local` so deletes route correctly).
  Future<List<_Draft>> _loadDrafts() async {
    try {
      final list = await api.feed.drafts();
      return list.map(_serverDraft).toList();
    } catch (_) {
      final local = await _readLocalDrafts();
      return local
          .map((d) => _Draft(
                id: '${d['at']}',
                text: '${d['t']}',
                time: d['at'] is num
                    ? DateTime.fromMillisecondsSinceEpoch((d['at'] as num).toInt())
                    : null,
                local: true,
              ))
          .toList();
    }
  }

  Future<void> _deleteDraft(_Draft d) async {
    if (d.local) {
      final drafts = await _readLocalDrafts();
      drafts.removeWhere((e) => '${e['at']}' == d.id);
      await _writeLocalDrafts(drafts);
    } else {
      try {
        await api.feed.deleteDraft(d.id);
      } catch (_) {/* best effort — leave it for a later sync */}
    }
  }

  /// Restores [d] into the composer, preserving the current text as a new
  /// draft so the buffer isn't lost.
  Future<void> _restoreDraft(_Draft d) async {
    final current = _text.text.trim();
    if (current.isNotEmpty && current != d.text) {
      try {
        await api.feed.saveDraft(_composerSnapshot(current));
      } catch (_) {
        final keep = await _readLocalDrafts();
        keep.insert(
            0, {'t': current, 'at': DateTime.now().millisecondsSinceEpoch});
        await _writeLocalDrafts(keep);
      }
    }
    if (mounted) setState(() => _text.text = d.text);
  }

  Future<void> _openDrafts() async {
    var drafts = await _loadDrafts();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Drafts',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: _text.text.trim().isEmpty
                    ? null
                    : TextButton.icon(
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save current'),
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _saveAsDraft();
                        },
                      ),
              ),
              if (drafts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No drafts yet.'),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in drafts)
                        ListTile(
                          title: Text(d.text,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle:
                              d.time != null ? Text(shortAgo(d.time!)) : null,
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 20,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .error),
                            onPressed: () async {
                              await _deleteDraft(d);
                              drafts =
                                  drafts.where((e) => e.id != d.id).toList();
                              if (sheetContext.mounted) setSheet(() {});
                            },
                          ),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _restoreDraft(d);
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _mentionTimer?.cancel();
    _text.removeListener(_saveDraft);
    _text.dispose();
    for (final c in _options) {
      c.dispose();
    }
    for (final c in _threadParts) {
      c.dispose();
    }
    super.dispose();
  }

  void _togglePoll() => setState(() => _poll = !_poll);

  void _addThreadPart() =>
      setState(() => _threadParts.add(TextEditingController()));

  void _removeThreadPart(int i) =>
      setState(() => _threadParts.removeAt(i).dispose());

  /// Detects an `@token` at the caret and searches users for autocomplete.
  void _onTextChanged(String _) {
    setState(() {});
    final sel = _text.selection;
    final pos = sel.baseOffset;
    if (pos < 0) {
      if (_mentions.isNotEmpty) setState(() => _mentions = const []);
      return;
    }
    final before = _text.text.substring(0, pos);
    final m = RegExp(r'@(\w{1,30})$').firstMatch(before);
    _mentionTimer?.cancel();
    if (m == null) {
      if (_mentions.isNotEmpty) setState(() => _mentions = const []);
      return;
    }
    final query = m.group(1)!;
    _mentionTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final users = await api.users.search(query);
        if (mounted) setState(() => _mentions = users.take(5).toList());
      } catch (_) {/* ignore */}
    });
  }

  /// Replaces the `@token` at the caret with the chosen @username.
  void _insertMention(PublicUser u) {
    final handle = u.username ?? u.name;
    final pos = _text.selection.baseOffset;
    if (pos < 0) return;
    final before = _text.text.substring(0, pos);
    final after = _text.text.substring(pos);
    final replaced = before.replaceFirst(RegExp(r'@\w*$'), '@$handle ');
    final next = '$replaced$after';
    setState(() {
      _text.text = next;
      _text.selection = TextSelection.collapsed(offset: replaced.length);
      _mentions = const [];
    });
  }

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
      final results = await geocodePlaces(query);
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
      // Validate the poll before any uploads start.
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

      // Host photos on Cloudinary when configured; inline base64 otherwise.
      final media = <PostMedia>[];
      for (final b in _photos) {
        final url = await cloudinaryUploadImage(b, folder: 'posts');
        media.add(url != null
            ? PostMedia(type: 'image', url: url)
            : PostMedia(type: 'image', base64: base64Encode(b)));
      }

      final first = await api.feed.createPost(PostCreate(
        text: _text.text.trim(),
        media: media,
        poll: poll,
        quoteOf: widget.quoteOf,
        placeName: _placeName,
        placeLatitude: _placeLat,
        placeLongitude: _placeLng,
        commentPolicy: _commentPolicy == 'everyone' ? null : _commentPolicy,
        likesDisabled: _likesDisabled ? true : null,
        minSubTier: _subscribersOnly ? 1 : null,
      ));
      // Publish each continuation as a reply to the first post — a flat
      // self-thread. Done after the head is up so its id is the parent.
      for (final c in _threadParts) {
        final t = c.text.trim();
        if (t.isEmpty) continue;
        await api.feed.createPost(PostCreate(text: t, parentId: first.id));
      }
      _clearDraft();
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
      appBar: OkayAppBar(
        title: const Text('New post'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drafts_outlined),
            tooltip: 'Drafts',
            onPressed: _openDrafts,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
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
            onChanged: _onTextChanged,
            decoration: InputDecoration(
              hintText:
                  widget.quoteOf != null ? 'Add a comment…' : "What's happening?",
              border: InputBorder.none,
              filled: false,
            ),
          ),
          if (_mentions.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final u in _mentions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: Avatar(url: u.picture, name: u.name, radius: 10),
                        label: Text('@${u.username ?? u.name}'),
                        onPressed: () => _insertMention(u),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.quotedPreview != null) _quotedPreview(widget.quotedPreview!),
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
          for (var i = 0; i < _threadParts.length; i++)
            _threadPartEditor(context, i),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _posting ? null : _addThreadPart,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: Text(
                    _threadParts.isEmpty ? 'Add to thread' : 'Add another post'),
              ),
            ),
          ),
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

  /// One continuation post in the thread — a connector rail down the left
  /// and a text field, with a control to drop it.
  Widget _threadPartEditor(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4, right: 8),
            child: Container(width: 2, height: 28, color: scheme.outlineVariant),
          ),
          Expanded(
            child: TextField(
              controller: _threadParts[i],
              maxLines: null,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Add another post…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove',
            onPressed: () => _removeThreadPart(i),
          ),
        ],
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

/// A draft as shown in the Drafts sheet, normalized across its source so the
/// UI doesn't care whether it came from the server or local fallback storage.
class _Draft {
  const _Draft({
    required this.id,
    required this.text,
    required this.time,
    required this.local,
  });

  /// Server draft id, or (for local fallback drafts) the legacy `at` stamp.
  final String id;
  final String text;
  final DateTime? time;

  /// Whether this draft lives in local secure storage (vs. on the server).
  final bool local;
}
