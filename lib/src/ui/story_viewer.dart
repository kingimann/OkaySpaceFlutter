import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Full-screen story viewer for a single user's stories.
///
/// Auto-advances through the stories, marks each viewed, and offers a reply
/// box. Tap left/right to go back/forward; tap and hold pauses.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen(
      {super.key, required this.userId, required this.userName});

  final String userId;
  final String userName;

  static Future<void> open(
          BuildContext context, String userId, String userName) =>
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerScreen(userId: userId, userName: userName),
      ));

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  static const _perStory = Duration(seconds: 5);

  late Future<List<Story>> _stories;
  List<Story> _items = const [];
  int _index = 0;
  Timer? _timer;
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stories = api.stories.userStories(widget.userId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reply.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer(_perStory, _next);
    final story = _items[_index];
    api.stories.markViewed(story.id).catchError((_) {});
  }

  void _next() {
    if (_index < _items.length - 1) {
      setState(() => _index++);
      _start();
    } else {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _start();
    }
  }

  Uint8List? _decode(String base64Data) {
    if (base64Data.isEmpty) return null;
    final comma = base64Data.indexOf(',');
    final raw = base64Data.startsWith('data:') && comma != -1
        ? base64Data.substring(comma + 1)
        : base64Data;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  bool get _isMine => widget.userId == currentUserId;

  Future<void> _sendReply([String? quick]) async {
    final text = quick ?? _reply.text.trim();
    if (text.isEmpty) return;
    final story = _items[_index];
    if (quick == null) _reply.clear();
    FocusScope.of(context).unfocus();
    try {
      await api.stories.reply(story.id, text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(quick != null ? 'Sent $quick' : 'Reply sent')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteStory() async {
    _timer?.cancel();
    final story = _items[_index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete story?'),
        content: const Text('This story will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) _start();
      return;
    }
    try {
      await api.stories.delete(story.id);
      if (!mounted) return;
      setState(() => _items = List.of(_items)..removeAt(_index));
      if (_items.isEmpty) {
        Navigator.of(context).maybePop();
      } else {
        _index = _index.clamp(0, _items.length - 1);
        _start();
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
        _start();
      }
    }
  }

  /// Shows who viewed this story (works for your own stories).
  Future<void> _showViewers(Story story) async {
    _timer?.cancel(); // pause auto-advance while the sheet is open
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => FutureBuilder<List<StoryViewer>>(
        future: api.stories.viewers(story.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()));
          }
          final viewers = snap.data ?? const [];
          if (viewers.isEmpty) {
            return const SizedBox(
                height: 160,
                child: Center(child: Text('No viewers yet.')));
          }
          return ListView.builder(
            shrinkWrap: true,
            itemCount: viewers.length,
            itemBuilder: (context, i) {
              final v = viewers[i];
              return ListTile(
                leading: Avatar(url: v.picture, name: v.name),
                title: Text(v.name),
                subtitle: v.username != null ? Text('@${v.username}') : null,
                trailing: Text(shortAgo(v.viewedAt),
                    style: Theme.of(context).textTheme.bodySmall),
              );
            },
          );
        },
      ),
    );
    if (mounted) _start(); // resume
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<Story>>(
        future: _stories,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(messageFor(snapshot.error),
                  style: const TextStyle(color: Colors.white)),
            );
          }
          _items = snapshot.data ?? const [];
          if (_items.isEmpty) {
            return const Center(
              child: Text('No active stories.',
                  style: TextStyle(color: Colors.white)),
            );
          }
          // Kick off the timer once the data is ready.
          if (_timer == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _start());
          }
          final story = _items[_index];
          final bytes = _decode(story.mediaBase64);

          return SafeArea(
            child: Stack(
              children: [
                // Media (tap zones for prev/next; long-press pauses).
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(
                          child: GestureDetector(
                        onTap: _prev,
                        onLongPressStart: (_) => _timer?.cancel(),
                        onLongPressEnd: (_) => _start(),
                      )),
                      Expanded(
                          child: GestureDetector(
                        onTap: _next,
                        onLongPressStart: (_) => _timer?.cancel(),
                        onLongPressEnd: (_) => _start(),
                      )),
                    ],
                  ),
                ),
                Center(
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : const Icon(Icons.broken_image,
                          color: Colors.white54, size: 64),
                ),
                // Progress bars + header.
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            Expanded(
                              child: Container(
                                height: 3,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: i <= _index
                                      ? Colors.white
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Avatar(
                              url: story.userPicture,
                              name: story.userName,
                              radius: 16),
                          const SizedBox(width: 8),
                          Text(widget.userName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showViewers(story),
                            icon: const Icon(Icons.visibility_outlined,
                                color: Colors.white, size: 18),
                            label: Text('${story.viewCount}',
                                style: const TextStyle(color: Colors.white)),
                          ),
                          if (_isMine)
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.white),
                              tooltip: 'Delete',
                              onPressed: _deleteStory,
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (story.caption != null && story.caption!.isNotEmpty)
                  Positioned(
                    bottom: 80,
                    left: 16,
                    right: 16,
                    child: Text(story.caption!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16)),
                  ),
                // Reply box (hidden on your own stories) + quick reactions.
                if (!_isMine)
                  Positioned(
                    bottom: 8,
                    left: 12,
                    right: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final e in const [
                              '❤️', '😂', '😮', '😢', '👏', '🔥'
                            ])
                              GestureDetector(
                                onTap: () => _sendReply(e),
                                child: Text(e,
                                    style: const TextStyle(fontSize: 28)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _reply,
                                style: const TextStyle(color: Colors.white),
                                onSubmitted: (_) => _sendReply(),
                                decoration: const InputDecoration(
                                  hintText: 'Reply…',
                                  hintStyle: TextStyle(color: Colors.white54),
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(
                                      borderSide:
                                          BorderSide(color: Colors.white54)),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: () => _sendReply(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
