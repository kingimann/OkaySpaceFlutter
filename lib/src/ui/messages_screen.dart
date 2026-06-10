import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../okayspace_api.dart';
import 'call_screen.dart';
import 'common.dart';
import 'linked_text.dart';

/// List of the current user's conversations.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<ConversationView>> _conversations;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _conversations = api.messaging.conversations();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _conversations = api.messaging.conversations());
    await _conversations;
  }

  Future<void> _newChat() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const _NewChatScreen()));
    if (mounted) _reload();
  }

  Future<void> _newGroup() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const _NewGroupScreen()));
    if (mounted) _reload();
  }

  String _title(ConversationView c) {
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  /// Long-press a conversation: mark read or delete it.
  void _convActions(ConversationView c) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined),
              title: const Text('Mark as read'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await api.messaging.markRead(c.id);
                } catch (_) {}
                if (mounted) _reload();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete conversation',
                  style: TextStyle(color: scheme.error)),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await api.messaging.delete(c.id);
                  if (mounted) {
                    showInfo(context, 'Deleted');
                    _reload();
                  }
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'New group',
            onPressed: _newGroup,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        child: const Icon(Icons.edit_square),
      ),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: AsyncList<ConversationView>(
                  future: _conversations,
                  loading: const ListSkeleton(),
                  emptyMessage: 'No conversations yet.',
                  emptyIcon: Icons.forum_outlined,
                  builder: (context, items) {
                    final filtered = _query.isEmpty
                        ? items
                        : items.where((c) {
                            final t = _title(c).toLowerCase();
                            final p = (c.lastMessage?.text ?? '').toLowerCase();
                            return t.contains(_query) || p.contains(_query);
                          }).toList();
                    if (filtered.isEmpty) {
                      return const CenteredMessage(
                          message: 'No matching conversations.',
                          icon: Icons.search_off);
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final title = _title(c);
                        return _ConversationTile(
                          conversation: c,
                          title: title,
                          onLongPress: () => _convActions(c),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  ChatScreen(conversation: c, title: title),
                            ));
                            if (mounted) _reload();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A styled conversation row: avatar (with online dot), name, last-message
/// preview, timestamp and an unread badge.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.title,
    required this.onTap,
    this.onLongPress,
  });

  final ConversationView conversation;
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// A short preview of the last message, with an icon label for non-text types.
  String _preview() {
    final m = conversation.lastMessage;
    if (m == null) return '';
    if (m.deleted) return 'Message deleted';
    if (m.text != null && m.text!.isNotEmpty) return m.text!;
    return switch (m.type) {
      'media' => '📷 Photo',
      'voice' => '🎤 Voice message',
      'gif' => 'GIF',
      'post' => 'Shared a post',
      'place' => '📍 Location',
      'money' => '💸 Payment',
      _ => 'New message',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = conversation.unreadCount > 0;
    final online = conversation.otherUser?.online ?? false;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onLongPress: onLongPress,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(
              url: conversation.avatar ?? conversation.otherUser?.picture,
              name: title,
              radius: 26),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        _preview(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread ? scheme.onSurface : scheme.outline,
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            Text(shortAgo(conversation.lastMessageAt!),
                style: TextStyle(
                    fontSize: 12,
                    color: unread ? scheme.primary : scheme.outline,
                    fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(height: 4),
          if (unread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${conversation.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A single conversation's messages with a composer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversation, required this.title});

  final ConversationView conversation;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Message> _items = const [];
  bool _loading = true;
  Object? _error;
  Timer? _poll;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _showJump = false;
  bool _sending = false;
  Message? _replyTo;
  Timer? _typingTimer;
  bool _typingSent = false;
  // Per-message keys so a reply quote can scroll to its original.
  final Map<String, GlobalKey> _msgKeys = {};
  String? _highlightId;
  Timer? _highlightTimer;
  late String _chatTitle = widget.title;

  // Per-conversation unsent-text drafts.
  final _storage = const FlutterSecureStorage();
  Timer? _draftTimer;
  // @mention autocomplete (group chats).
  List<PublicUser> _mentions = const [];
  // Auto-scroll to the first unread message, once, on open.
  final _unreadKey = GlobalKey();
  bool _scrolledToUnread = false;
  // Locally starred messages (per conversation).
  Set<String> _starred = {};
  // Expanded (Read more) long messages.
  final Set<String> _expanded = {};
  // Chat wallpaper tint (per conversation, local).
  Color? _bgTint;
  // Muted notifications (per conversation, local).
  bool _muted = false;
  // Chat text size multiplier (per conversation, local).
  double _textScale = 1.0;
  // Saved quick-reply phrases (shared across conversations, local).
  List<String> _quickReplies = const [];

  String get _convId => widget.conversation.id;
  String get _draftKey => 'okayspace.chat_draft.$_convId';
  String get _starKey => 'okayspace.chat_starred.$_convId';
  String get _bgKey => 'okayspace.chat_bg.$_convId';
  String get _muteKey => 'okayspace.chat_mute.$_convId';
  String get _scaleKey => 'okayspace.chat_scale.$_convId';
  static const _quickKey = 'okayspace.chat_quickreplies';

  @override
  void initState() {
    super.initState();
    _fetch();
    _loadDraft();
    _loadStarred();
    _loadPrefs();
    api.messaging.markRead(_convId).ignore();
    // Show the jump-to-latest button once scrolled away from the bottom
    // (offset 0 is the newest message in this reversed list).
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 320;
      if (show != _showJump) setState(() => _showJump = show);
    });
    // Light polling so new incoming messages appear while the chat is open.
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      _fetch(silent: true);
      api.messaging.pingPresence().ignore();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    _draftTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    try {
      final d = await _storage.read(key: _draftKey);
      if (d != null && d.isNotEmpty && mounted && _input.text.isEmpty) {
        _input.text = d;
      }
    } catch (_) {/* ignore */}
  }

  void _saveDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () {
      final t = _input.text;
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

  Future<void> _loadStarred() async {
    try {
      final d = await _storage.read(key: _starKey);
      if (d != null && d.isNotEmpty && mounted) {
        setState(() =>
            _starred = d.split('\n').where((s) => s.isNotEmpty).toSet());
      }
    } catch (_) {/* ignore */}
  }

  void _toggleStar(Message m) {
    setState(() {
      if (!_starred.remove(m.id)) _starred.add(m.id);
    });
    _storage.write(key: _starKey, value: _starred.join('\n')).ignore();
  }

  /// Loads per-conversation prefs: wallpaper tint, mute, text size, quick replies.
  Future<void> _loadPrefs() async {
    try {
      final bg = await _storage.read(key: _bgKey);
      final muted = await _storage.read(key: _muteKey);
      final scale = await _storage.read(key: _scaleKey);
      final quick = await _storage.read(key: _quickKey);
      if (!mounted) return;
      setState(() {
        final argb = int.tryParse(bg ?? '');
        _bgTint = (argb != null && argb != 0) ? Color(argb) : null;
        _muted = muted == '1';
        _textScale = double.tryParse(scale ?? '') ?? 1.0;
        if (quick != null && quick.isNotEmpty) {
          _quickReplies = quick.split('\n').where((s) => s.isNotEmpty).toList();
        }
      });
    } catch (_) {/* ignore */}
  }

  void _setBgTint(Color? c) {
    setState(() => _bgTint = c);
    if (c == null) {
      _storage.delete(key: _bgKey).ignore();
    } else {
      _storage.write(key: _bgKey, value: '${c.toARGB32()}').ignore();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _storage.write(key: _muteKey, value: _muted ? '1' : '0').ignore();
    showInfo(context,
        _muted ? 'Notifications muted' : 'Notifications unmuted');
  }

  void _setTextScale(double s) {
    setState(() => _textScale = s);
    _storage.write(key: _scaleKey, value: '$s').ignore();
  }

  void _saveQuickReplies(List<String> list) {
    setState(() => _quickReplies = list);
    _storage.write(key: _quickKey, value: list.join('\n')).ignore();
  }

  /// Wallpaper tint picker.
  void _chooseWallpaper() {
    const swatches = <Color?>[
      null,
      Color(0xFFE3F2FD),
      Color(0xFFE8F5E9),
      Color(0xFFFFF3E0),
      Color(0xFFF3E5F5),
      Color(0xFFFCE4EC),
      Color(0xFFEFEBE9),
      Color(0xFF263238),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chat wallpaper',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in swatches)
                    GestureDetector(
                      onTap: () {
                        _setBgTint(c);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: c ?? Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (_bgTint == c)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).dividerColor,
                            width: (_bgTint == c) ? 3 : 1,
                          ),
                        ),
                        child: c == null
                            ? const Icon(Icons.format_color_reset, size: 20)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Text-size chooser for chat bubbles.
  void _chooseTextSize() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Text size',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('The quick brown fox',
                    style: TextStyle(fontSize: 15 * _textScale)),
                Slider(
                  value: _textScale,
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  label: '${(_textScale * 100).round()}%',
                  onChanged: (v) {
                    setSheet(() {});
                    _setTextScale(v);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Manages the saved quick-reply phrases (add / remove).
  void _manageQuickReplies() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(c).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick replies',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                for (final q in _quickReplies)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(q),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final next = [..._quickReplies]..remove(q);
                        _saveQuickReplies(next);
                        setSheet(() {});
                      },
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add quick reply'),
                  onPressed: () async {
                    final text = await promptText(c, title: 'Quick reply');
                    if (text != null && text.trim().isNotEmpty) {
                      _saveQuickReplies([..._quickReplies, text.trim()]);
                      setSheet(() {});
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Jumps to the first message on or after a chosen calendar date.
  Future<void> _jumpToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2015),
      lastDate: now,
    );
    if (picked == null) return;
    // _items is newest-first; find the oldest message on/after picked.
    Message? target;
    for (final m in _items) {
      final ts = m.createdAt;
      if (!ts.isBefore(picked)) {
        target = m;
      }
    }
    if (target == null) {
      if (mounted) showInfo(context, 'No messages on or after that date');
      return;
    }
    _jumpTo(target.id);
  }

  /// Copies the whole conversation as plain text to the clipboard.
  void _exportChat() {
    final ordered = [..._items.where((m) => !m.deleted)]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final buf = StringBuffer('Conversation with $_chatTitle\n\n');
    for (final m in ordered) {
      final who = _isMine(m) ? 'You' : _senderName(m.senderId);
      final when = m.createdAt.toLocal().toString().split('.').first;
      final body = m.text ?? '[${m.type}]';
      buf.writeln('[$when] $who: $body');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    showInfo(context, 'Conversation copied to clipboard');
  }

  /// Shows who reacted to [m] (defensive about the reaction payload shape).
  void _reactionDetails(Message m) {
    String nameFor(Object? id) {
      final s = '$id';
      if (s == currentUserId) return 'You';
      if (s == widget.conversation.otherUser?.userId) {
        return widget.conversation.otherUser!.name;
      }
      final mem = widget.conversation.members.where((u) => u.userId == s);
      return mem.isNotEmpty ? mem.first.name : 'Someone';
    }

    final raw = m.raw['reactions'];
    final byEmoji = <String, List<String>>{};
    final counts = <String, int>{};
    if (raw is List) {
      for (final r in raw) {
        if (r is Map) {
          final e = '${r['emoji'] ?? r['reaction'] ?? ''}';
          if (e.isEmpty) continue;
          final uid =
              r['user_id'] ?? r['user'] ?? r['userId'] ?? r['name'];
          byEmoji.putIfAbsent(e, () => []).add(uid != null ? nameFor(uid) : '');
          counts[e] = (counts[e] ?? 0) + 1;
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) {
        final e = '$k';
        if (e.isEmpty) return;
        if (v is List) {
          byEmoji[e] = [for (final id in v) nameFor(id)];
          counts[e] = v.length;
        } else if (v is num) {
          counts[e] = v.toInt();
        }
      });
    }
    if (counts.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Reactions',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final e in counts.keys)
              ListTile(
                leading: Text(e, style: const TextStyle(fontSize: 24)),
                title: Text(() {
                  final names =
                      (byEmoji[e] ?? const []).where((n) => n.isNotEmpty);
                  return names.isNotEmpty
                      ? names.join(', ')
                      : '${counts[e]} reaction${counts[e] == 1 ? '' : 's'}';
                }()),
              ),
          ],
        ),
      ),
    );
  }

  void _showStarred() {
    final items = _items
        .where((m) => _starred.contains(m.id) && !m.deleted)
        .toList()
        .reversed
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Starred messages',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No starred messages yet.'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in items)
                    ListTile(
                      leading: const Icon(Icons.star, color: Color(0xFFF6C455)),
                      title: Text(m.text ?? '[${m.type}]',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(shortAgo(m.createdAt)),
                      onTap: () {
                        Navigator.pop(context);
                        _jumpTo(m.id);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Updates @mention suggestions from the word at the cursor (group chats).
  void _updateMentions() {
    if (!widget.conversation.isGroup) return;
    final sel = _input.selection.baseOffset;
    final text = _input.text;
    if (sel < 0 || sel > text.length) {
      if (_mentions.isNotEmpty) setState(() => _mentions = const []);
      return;
    }
    final before = text.substring(0, sel);
    final match = RegExp(r'@(\w*)$').firstMatch(before);
    if (match == null) {
      if (_mentions.isNotEmpty) setState(() => _mentions = const []);
      return;
    }
    final q = match.group(1)!.toLowerCase();
    final hits = widget.conversation.members.where((u) {
      if (u.userId == currentUserId) return false;
      final uname = (u.username ?? '').toLowerCase();
      return q.isEmpty ||
          uname.contains(q) ||
          u.name.toLowerCase().contains(q);
    }).take(5).toList();
    setState(() => _mentions = hits);
  }

  void _insertMention(PublicUser u) {
    final handle = u.username ?? u.name.replaceAll(' ', '');
    final sel = _input.selection.baseOffset;
    final text = _input.text;
    final before = text.substring(0, sel);
    final start = before.lastIndexOf('@');
    if (start < 0) return;
    final newBefore = '${before.substring(0, start)}@$handle ';
    final after = text.substring(sel);
    _input.text = newBefore + after;
    _input.selection =
        TextSelection.collapsed(offset: newBefore.length);
    setState(() => _mentions = const []);
  }

  // Multi-select mode.
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  void _toggleSelect(Message m) {
    setState(() {
      if (!_selected.remove(m.id)) _selected.add(m.id);
    });
  }

  void _exitSelection() => setState(_selected.clear);

  Future<void> _deleteSelected() async {
    final ids = _items
        .where((m) => _selected.contains(m.id) && _isMine(m) && !m.deleted)
        .map((m) => m.id)
        .toList();
    _exitSelection();
    if (ids.isEmpty) return;
    for (final id in ids) {
      try {
        await api.messaging.deleteMessage(_convId, id);
      } catch (_) {/* skip */}
    }
    await _fetch(silent: true);
  }

  Future<void> _forwardSelected() async {
    final msgs = _items
        .where((m) => _selected.contains(m.id) && (m.text ?? '').isNotEmpty)
        .toList();
    if (msgs.isEmpty) {
      _exitSelection();
      return;
    }
    final target = await pickConversation(context);
    if (target == null || !mounted) return;
    _exitSelection();
    for (final m in msgs) {
      try {
        await api.messaging.sendText(target.id, m.text!);
      } catch (_) {/* skip */}
    }
    if (mounted) showInfo(context, 'Forwarded ${msgs.length}');
  }

  void _copySelected() {
    final text = _items
        .where((m) => _selected.contains(m.id) && (m.text ?? '').isNotEmpty)
        .map((m) => m.text!)
        .join('\n');
    _exitSelection();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    showInfo(context, 'Copied');
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_items.where((m) => !m.deleted).map((m) => m.id));
    });
  }

  /// Broadcasts typing presence to the other participant(s), debounced; sends
  /// 'idle' after a short pause.
  void _onTyping(String _) {
    if (!_typingSent) {
      _typingSent = true;
      api.messaging.setPresence(_convId, 'typing').ignore();
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
    _saveDraft();
    _updateMentions();
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_typingSent) {
      _typingSent = false;
      api.messaging.setPresence(_convId, 'idle').ignore();
    }
  }

  /// Loads messages. [silent] updates in place without showing the spinner
  /// and ignores errors (used by the poll).
  Future<void> _fetch({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final msgs = await api.messaging.messages(_convId);
      if (!mounted) return;
      // Skip the rebuild when a silent poll returns no changes, so it can't
      // interrupt the UI (e.g. dismiss an open menu) every few seconds.
      if (silent && !_loading && _error == null && _sameMessages(msgs)) {
        return;
      }
      setState(() {
        _items = msgs;
        _loading = false;
        _error = null;
      });
      // On first load, jump to where the unread messages begin.
      if (!_scrolledToUnread &&
          widget.conversation.unreadCount > 0 &&
          msgs.length > widget.conversation.unreadCount) {
        _scrolledToUnread = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _unreadKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300), alignment: 0.3);
          }
        });
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// Whether [msgs] matches the currently displayed list (count + last
  /// message id / edited time), used to avoid redundant poll rebuilds.
  bool _sameMessages(List<Message> msgs) {
    if (msgs.length != _items.length) return false;
    if (msgs.isEmpty) return true;
    final a = msgs.last, b = _items.last;
    return a.id == b.id && a.editedAt == b.editedAt && a.deleted == b.deleted;
  }

  Future<void> _reload() => _fetch();

  /// Animates to the newest message (offset 0 in this reversed list).
  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Whether [msg] was sent by the current user.
  bool _isMine(Message msg) {
    final otherId = widget.conversation.otherUser?.userId;
    if (currentUserId != null) return msg.senderId == currentUserId;
    // Fallback for direct chats before the current user id has loaded.
    return otherId != null && msg.senderId != otherId;
  }

  /// Display name for a sender (group chats), from the member list.
  String _senderName(String id) {
    final m = widget.conversation.members.where((u) => u.userId == id);
    return m.isNotEmpty ? m.first.name : 'Member';
  }

  /// Read state of my last message in a direct chat.
  String _receipt(Message m) {
    final other = widget.conversation.otherUser?.userId;
    if (other != null && m.readBy.contains(other)) return 'Seen';
    if (other != null && m.deliveredBy.contains(other)) return 'Delivered';
    return 'Sent';
  }

  Widget _buildMessages() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return CenteredMessage(
          message: messageFor(_error), icon: Icons.error_outline);
    }
    if (_items.isEmpty) {
      return const CenteredMessage(
          message: 'Say hello 👋', icon: Icons.waving_hand_outlined);
    }

    final byId = {for (final m in _items) m.id: m};
    final isGroup = widget.conversation.isGroup;
    // Id of my most recent (non-deleted) message — gets the read receipt.
    String? lastMineId;
    for (final m in _items) {
      if (_isMine(m) && !m.deleted) lastMineId = m.id;
    }

    // Interleave day separators (and an unread marker) between messages
    // chronologically, then render reversed so the newest sits at the bottom.
    final unread = widget.conversation.unreadCount;
    final firstUnread =
        (unread > 0 && unread < _items.length) ? _items.length - unread : -1;
    final rows = <Object>[];
    DateTime? lastDay;
    for (var idx = 0; idx < _items.length; idx++) {
      final m = _items[idx];
      final c = m.createdAt.toLocal();
      final day = DateTime(c.year, c.month, c.day);
      if (lastDay == null || day != lastDay) {
        rows.add(day);
        lastDay = day;
      }
      if (idx == firstUnread) rows.add(_unreadMarker);
      rows.add(m);
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final row = rows[rows.length - 1 - i];
          if (row is DateTime) return _DateSeparator(day: row);
          if (identical(row, _unreadMarker)) {
            return KeyedSubtree(key: _unreadKey, child: const _UnreadDivider());
          }
          final msg = row as Message;
          final mine = _isMine(msg);
          final key = _msgKeys.putIfAbsent(msg.id, GlobalKey.new);
          final selected = _selected.contains(msg.id);
          final bubble = _MessageBubble(
            message: msg,
            mine: mine,
            highlight: _highlightId == msg.id,
            selected: selected,
            starred: _starred.contains(msg.id),
            expanded: _expanded.contains(msg.id),
            onToggleExpand: () => setState(() {
              if (!_expanded.remove(msg.id)) _expanded.add(msg.id);
            }),
            replyTo: msg.replyToId != null ? byId[msg.replyToId] : null,
            onTapReply: msg.replyToId != null
                ? () => _jumpTo(msg.replyToId!)
                : null,
            onTapReactions: () => _reactionDetails(msg),
            senderName:
                (isGroup && !mine && !msg.deleted) ? _senderName(msg.senderId) : null,
            receipt: (!isGroup &&
                    mine &&
                    msg.id == lastMineId &&
                    widget.conversation.receiptsEnabled)
                ? _receipt(msg)
                : null,
            // In selection mode, a tap toggles selection instead of opening.
            onTap: _selectionMode ? () => _toggleSelect(msg) : null,
            onLongPress: _selectionMode
                ? () => _toggleSelect(msg)
                : (msg.deleted ? null : () => _messageActions(msg, mine)),
            onDoubleTap: (_selectionMode || msg.deleted)
                ? null
                : () => _run(
                    () => api.messaging.reactToMessage(_convId, msg.id, '❤️')),
          );
          if (msg.deleted) return KeyedSubtree(key: key, child: bubble);
          // Swipe right to reply; swipe left to delete your own messages.
          final canDelete = _isMine(msg);
          return KeyedSubtree(
            key: key,
            child: Dismissible(
              key: ValueKey('swipe-${msg.id}'),
              direction: canDelete
                  ? DismissDirection.horizontal
                  : DismissDirection.startToEnd,
              dismissThresholds: const {
                DismissDirection.startToEnd: 0.2,
                DismissDirection.endToStart: 0.35,
              },
              confirmDismiss: (dir) async {
                if (dir == DismissDirection.startToEnd) {
                  setState(() => _replyTo = msg);
                  return false;
                }
                // endToStart → delete own message.
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete message?'),
                    content: const Text(
                        'This message will be removed for everyone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await _run(
                      () => api.messaging.deleteMessage(_convId, msg.id));
                }
                return false;
              },
              background: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.reply,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ),
              secondaryBackground: canDelete
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    )
                  : null,
              child: bubble,
            ),
          );
        },
      ),
    );
  }

  /// Scrolls to the message with [id] (if built) and briefly highlights it.
  void _jumpTo(String id) {
    final ctx = _msgKeys[id]?.currentContext;
    if (ctx == null) {
      showInfo(context, 'Original message not loaded');
      return;
    }
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.4,
        curve: Curves.easeOut);
    setState(() => _highlightId = id);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  String _convTitle(ConversationView c) {
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  /// Forwards [msg]'s text to another conversation the user picks.
  Future<void> _forward(Message msg) async {
    final text = msg.text;
    if (text == null || text.isEmpty) return;
    final convs = await api.messaging
        .conversations()
        .catchError((_) => <ConversationView>[]);
    if (!mounted) return;
    final target = await showModalBottomSheet<ConversationView>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Forward to',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in convs)
                    ListTile(
                      leading: Avatar(
                          url: c.avatar ?? c.otherUser?.picture,
                          name: _convTitle(c)),
                      title: Text(_convTitle(c),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await api.messaging.sendText(target.id, text);
      if (mounted) showInfo(context, 'Forwarded');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// A larger emoji grid for reacting with something beyond the quick set.
  void _moreReactions(Message msg) {
    const emojis = [
      '👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '🎉',
      '👏', '😍', '😡', '🤔', '🙌', '💯', '✅', '👀',
      '🥳', '😎', '🤝', '😭', '😅', '🤯', '💀', '🫶'
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final e in emojis)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.pop(context);
                    _run(() =>
                        api.messaging.reactToMessage(_convId, msg.id, e));
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sheet listing the members of a group conversation.
  void _showMembers() {
    final members = widget.conversation.members;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text('${members.length} members',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in members)
                    ListTile(
                      leading: Avatar(url: u.picture, name: u.name),
                      title: Text(u.name),
                      subtitle: u.username != null ? Text(u.handle) : null,
                      trailing: u.userId == widget.conversation.ownerId
                          ? const Text('Owner')
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sheet showing delivery/read details for a message.
  void _messageInfo(Message msg) {
    String names(List<String> ids) {
      if (ids.isEmpty) return '—';
      return ids.map((id) {
        if (id == widget.conversation.otherUser?.userId) {
          return widget.conversation.otherUser!.name;
        }
        final m = widget.conversation.members.where((u) => u.userId == id);
        return m.isNotEmpty ? m.first.name : 'Someone';
      }).join(', ');
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Message info',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('Read by'),
              subtitle: Text(names(msg.readBy)),
            ),
            ListTile(
              leading: const Icon(Icons.check),
              title: const Text('Delivered to'),
              subtitle: Text(names(msg.deliveredBy)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Sent'),
              subtitle: Text(msg.createdAt.toLocal().toString()),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner sheet listing the conversation's pinned messages.
  void _showPinned() {
    final pinned = _items.where((m) => m.pinned && !m.deleted).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Pinned messages',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final m in pinned)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(m.text ?? '[${m.type}]',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(shortAgo(m.createdAt)),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Unpin',
                  onPressed: () {
                    Navigator.pop(context);
                    _run(() => api.messaging.pinMessage(_convId, m.id));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _call({bool video = false}) {
    CallScreen.open(
      context,
      conversationId: _convId,
      title: _chatTitle,
      avatarUrl: widget.conversation.avatar ??
          widget.conversation.otherUser?.picture,
      video: video,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final replyTo = _replyTo?.id;
    setState(() => _sending = true);
    try {
      await api.messaging
          .send(_convId, MessageCreate.text(text, replyTo: replyTo));
      _input.clear();
      _clearDraft();
      _stopTyping();
      if (mounted) {
        setState(() {
          _mentions = const [];
          _replyTo = null;
        });
      }
      await _fetch(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Attachment chooser: photo or location.
  void _attachMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(context);
                _attachImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Location'),
              onTap: () {
                Navigator.pop(context);
                _attachLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Picks a point on a map and sends it as a location message.
  Future<void> _attachLocation() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const _LocationPickerScreen()),
    );
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await api.messaging.send(
        _convId,
        MessageCreate(
          type: 'place',
          placeName: 'Shared location',
          placeLatitude: picked.latitude,
          placeLongitude: picked.longitude,
        ),
      );
      await _fetch(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Searches messages in this conversation and jumps to the chosen one.
  void _searchMessages() {
    final ctrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (context, setSheet) {
            final q = ctrl.text.trim().toLowerCase();
            final matches = q.isEmpty
                ? const <Message>[]
                : _items
                    .where((m) =>
                        !m.deleted &&
                        (m.text ?? '').toLowerCase().contains(q))
                    .toList()
                    .reversed
                    .toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    onChanged: (_) => setSheet(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search this conversation',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (q.isNotEmpty && matches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No messages found.'),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in matches)
                        ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(m.text ?? '',
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(shortAgo(m.createdAt)),
                          onTap: () {
                            Navigator.pop(context);
                            _jumpTo(m.id);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  /// Picks a photo and sends it as a media message.
  Future<void> _attachImage() async {
    if (_sending) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final replyTo = _replyTo?.id;
    setState(() => _sending = true);
    try {
      await api.messaging.send(
        _convId,
        MessageCreate(
          type: 'media',
          media: [PostMedia(type: 'image', base64: base64Encode(bytes))],
          replyTo: replyTo,
        ),
      );
      if (mounted) setState(() => _replyTo = null);
      await _fetch(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _run(Future<void> Function() op, [String? ok]) async {
    try {
      await op();
      if (ok != null && mounted) showInfo(context, ok);
      await _fetch(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Long-press a message: react, copy, pin and (for own messages) edit/delete.
  void _messageActions(Message msg, bool mine) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in const ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.pop(context);
                        _run(() =>
                            api.messaging.reactToMessage(_convId, msg.id, e));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.pop(context);
                      _moreReactions(msg);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.add_reaction_outlined, size: 26),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
              },
            ),
            ListTile(
              leading: Icon(
                  _starred.contains(msg.id) ? Icons.star : Icons.star_border),
              title: Text(_starred.contains(msg.id) ? 'Unstar' : 'Star'),
              onTap: () {
                Navigator.pop(context);
                _toggleStar(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(context);
                _toggleSelect(msg);
              },
            ),
            if (msg.text != null && msg.text!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(context);
                  _forward(msg);
                },
              ),
            if (msg.text != null && msg.text!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text!));
                  Navigator.pop(context);
                  showInfo(context, 'Copied');
                },
              ),
            ListTile(
              leading: Icon(msg.pinned
                  ? Icons.push_pin
                  : Icons.push_pin_outlined),
              title: Text(msg.pinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(context);
                _run(() => api.messaging.pinMessage(_convId, msg.id));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Info'),
              onTap: () {
                Navigator.pop(context);
                _messageInfo(msg);
              },
            ),
            if (mine && msg.text != null) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () async {
                  Navigator.pop(context);
                  final edited = await promptText(context,
                      title: 'Edit message', initial: msg.text);
                  if (edited != null && edited.trim().isNotEmpty) {
                    _run(() =>
                        api.messaging.editMessage(_convId, msg.id, edited.trim()));
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Delete',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _run(() => api.messaging.deleteMessage(_convId, msg.id),
                      'Deleted');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Conversation overflow menu: disappearing messages, leave, delete.
  void _conversationMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Starred messages'),
              onTap: () {
                Navigator.pop(context);
                _showStarred();
              },
            ),
            ListTile(
              leading: Icon(
                  _muted ? Icons.notifications_off : Icons.notifications_none),
              title: Text(_muted ? 'Unmute notifications' : 'Mute notifications'),
              onTap: () {
                Navigator.pop(context);
                _toggleMute();
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Jump to date'),
              onTap: () {
                Navigator.pop(context);
                _jumpToDate();
              },
            ),
            ListTile(
              leading: const Icon(Icons.wallpaper_outlined),
              title: const Text('Chat wallpaper'),
              onTap: () {
                Navigator.pop(context);
                _chooseWallpaper();
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_size),
              title: const Text('Text size'),
              onTap: () {
                Navigator.pop(context);
                _chooseTextSize();
              },
            ),
            ListTile(
              leading: const Icon(Icons.quickreply_outlined),
              title: const Text('Quick replies'),
              onTap: () {
                Navigator.pop(context);
                _manageQuickReplies();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export conversation'),
              onTap: () {
                Navigator.pop(context);
                _exportChat();
              },
            ),
            if (widget.conversation.isGroup)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename group'),
                onTap: () async {
                  Navigator.pop(context);
                  final name = await promptText(context,
                      title: 'Group name',
                      action: 'Save',
                      initial: _chatTitle);
                  if (name == null) return;
                  await _run(
                      () => api.messaging.updateGroup(_convId, {'name': name}),
                      'Renamed');
                  if (mounted) setState(() => _chatTitle = name);
                },
              ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Disappearing messages'),
              onTap: () {
                Navigator.pop(context);
                _disappearing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Leave conversation'),
              onTap: () {
                Navigator.pop(context);
                _run(() => api.messaging.leave(_convId), 'Left conversation')
                    .then((_) {
                  if (mounted) Navigator.pop(context);
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete conversation',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _run(() => api.messaging.delete(_convId), 'Deleted')
                    .then((_) {
                  if (mounted) Navigator.pop(context);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _disappearing() async {
    final seconds = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Disappearing messages',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final o in const [
              ('Off', 0),
              ('24 hours', 86400),
              ('7 days', 604800),
              ('90 days', 7776000),
            ])
              ListTile(
                title: Text(o.$1),
                onTap: () => Navigator.pop(context, o.$2),
              ),
          ],
        ),
      ),
    );
    if (seconds == null) return;
    _run(() => api.messaging.setDisappearing(_convId, seconds), 'Updated');
  }

  @override
  Widget build(BuildContext context) {
    final other = widget.conversation.otherUser;
    return Scaffold(
      appBar: _selectionMode
          ? OkayAppBar(
              leading: IconButton(
                  icon: const Icon(Icons.close), onPressed: _exitSelection),
              title: Text('${_selected.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select all',
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                  onPressed: _copySelected,
                ),
                IconButton(
                  icon: const Icon(Icons.forward),
                  tooltip: 'Forward',
                  onPressed: _forwardSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : OkayAppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(
                url: widget.conversation.avatar ?? other?.picture,
                name: _chatTitle,
                radius: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(_chatTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      if (_muted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.notifications_off, size: 14),
                        ),
                    ],
                  ),
                  if (other != null)
                    Text(other.online ? 'Online' : 'Offline',
                        style: TextStyle(
                            fontSize: 12,
                            color: other.online
                                ? const Color(0xFF22C55E)
                                : Theme.of(context).colorScheme.outline))
                  else if (widget.conversation.isGroup)
                    Text('${widget.conversation.members.length} members',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search in chat',
            onPressed: _searchMessages,
          ),
          if (widget.conversation.isGroup)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'Members',
              onPressed: _showMembers,
            ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
            onPressed: () => _call(video: true),
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Voice call',
            onPressed: () => _call(),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onPressed: _conversationMenu,
          ),
        ],
      ),
      body: MaxWidth(
        child: Column(
        children: [
          if (_items.any((m) => m.pinned && !m.deleted))
            _PinnedBanner(
              count: _items.where((m) => m.pinned && !m.deleted).length,
              onTap: _showPinned,
            ),
          Expanded(
            child: Stack(
              children: [
                if (_bgTint != null) Positioned.fill(child: ColoredBox(color: _bgTint!)),
                MediaQuery.withClampedTextScaling(
                  minScaleFactor: _textScale,
                  maxScaleFactor: _textScale,
                  child: _buildMessages(),
                ),
                if (_showJump)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'jumpToLatest',
                      onPressed: () => _scroll.animateTo(0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut),
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),
          if (_replyTo != null)
            _ReplyPreview(
              message: _replyTo!,
              senderName: widget.conversation.isGroup && !_isMine(_replyTo!)
                  ? _senderName(_replyTo!.senderId)
                  : (_isMine(_replyTo!) ? 'yourself' : widget.title),
              onCancel: () => setState(() => _replyTo = null),
            ),
          if (_mentions.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final u in _mentions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar:
                            Avatar(url: u.picture, name: u.name, radius: 10),
                        label: Text('@${u.username ?? u.name}'),
                        onPressed: () => _insertMention(u),
                      ),
                    ),
                ],
              ),
            ),
          if (_quickReplies.isNotEmpty && _input.text.trim().isEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final q in _quickReplies)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(q,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () {
                          setState(() {
                            _input.text = q;
                            _input.selection = TextSelection.collapsed(
                                offset: _input.text.length);
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Attach',
                    onPressed: _sending ? null : _attachMenu,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onChanged: _onTyping,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message,
      this.mine = false,
      this.highlight = false,
      this.selected = false,
      this.starred = false,
      this.expanded = false,
      this.onToggleExpand,
      this.onTap,
      this.onLongPress,
      this.onDoubleTap,
      this.onTapReply,
      this.onTapReactions,
      this.replyTo,
      this.senderName,
      this.receipt});

  final Message message;
  final bool mine;

  /// Briefly true when this message was jumped-to from a reply quote.
  final bool highlight;

  /// True when selected in multi-select mode.
  final bool selected;

  /// True when locally starred.
  final bool starred;

  /// Long-message "Read more" expansion state + toggle.
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  /// Tapped the reply quote — jumps to the original message.
  final VoidCallback? onTapReply;

  /// Tapped the reaction summary — shows who reacted.
  final VoidCallback? onTapReactions;

  /// The message this one is replying to (resolved), if any.
  final Message? replyTo;

  /// Sender's name, shown above the bubble in group chats (null to hide).
  final String? senderName;

  /// 'Sent' / 'Delivered' / 'Seen' for my last message (null to hide).
  final String? receipt;

  /// Aggregates raw reaction payloads into "emoji×count" chips.
  List<String> _reactionChips() {
    final raw = message.raw['reactions'];
    final counts = <String, int>{};
    if (raw is List) {
      for (final r in raw) {
        if (r is Map) {
          final e = '${r['emoji'] ?? r['reaction'] ?? ''}';
          if (e.isNotEmpty) counts[e] = (counts[e] ?? 0) + 1;
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) {
        final n = v is List ? v.length : (v is num ? v.toInt() : 1);
        if ('$k'.isNotEmpty) counts['$k'] = n;
      });
    }
    return [for (final e in counts.entries) '${e.key}${e.value > 1 ? ' ${e.value}' : ''}'];
  }

  /// Renders the first attached photo (network url, or base64 before refetch).
  /// Tapping opens a full-screen, zoomable viewer.
  /// A small non-interactive map preview for a shared location.
  Widget _placeCard(double lat, double lng) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 220,
        height: 140,
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(lat, lng),
              initialZoom: 14,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ca.okayspace.app',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: LatLng(lat, lng),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_pin,
                      color: Colors.red, size: 36),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaThumb(BuildContext context) {
    final m = message.media.first;
    ImageProvider? provider;
    if (m.url != null && m.url!.isNotEmpty) {
      provider = NetworkImage(m.url!);
    } else if (m.base64 != null && m.base64!.isNotEmpty) {
      provider = MemoryImage(base64Decode(m.base64!));
    }
    if (provider == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImageViewer(provider: provider!),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMedia = message.media.isNotEmpty && !message.deleted;
    final placeLat = (message.raw['place_latitude'] as num?)?.toDouble();
    final placeLng = (message.raw['place_longitude'] as num?)?.toDouble();
    final hasPlace = message.type == 'place' &&
        !message.deleted &&
        placeLat != null &&
        placeLng != null;
    final typeLabel = switch (message.type) {
      'post' => '📄 Shared a post',
      'place' => '📍 Location',
      'money' => '💸 Payment',
      'gif' => 'GIF',
      'voice' => '🎤 Voice message',
      'contact' => '👤 Contact',
      _ => '[${message.type}]',
    };
    final bodyText = message.deleted
        ? 'Message deleted'
        : (message.text ?? (hasMedia || hasPlace ? '' : typeLabel));
    // A short, all-emoji message renders large with no bubble (like WhatsApp).
    final t = (message.text ?? '').trim();
    final emojiOnly = !message.deleted &&
        !hasMedia &&
        !hasPlace &&
        message.replyToId == null &&
        t.isNotEmpty &&
        t.runes.length <= 8 &&
        !RegExp(r'[A-Za-z0-9]').hasMatch(t) &&
        RegExp(r'[^\x00-\x7F]').hasMatch(t);
    // Outgoing bubble = a dark tint of the current accent (teal by default,
    // matching okayspace.ca's WhatsApp-style chat).
    final bg = emojiOnly
        ? Colors.transparent
        : mine
            ? HSLColor.fromColor(scheme.primary).withLightness(0.22).toColor()
            : scheme.surfaceContainerHighest;
    final fg = mine ? OkayColors.textPrimary : scheme.onSurface;
    const radius = Radius.circular(18);
    final reactions = _reactionChips();
    return Container(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onDoubleTap: onDoubleTap,
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: radius,
                  topRight: radius,
                  bottomLeft: mine ? radius : const Radius.circular(4),
                  bottomRight: mine ? const Radius.circular(4) : radius,
                ),
                border: highlight
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (senderName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(senderName!,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary)),
                    ),
                  if (message.replyToId != null)
                    GestureDetector(
                      onTap: onTapReply,
                      child: Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                            left: BorderSide(
                                color: fg.withValues(alpha: 0.5), width: 3)),
                      ),
                      child: Text(
                          replyTo != null
                              ? (replyTo!.deleted
                                  ? 'Deleted message'
                                  : (replyTo!.text ?? '[${replyTo!.type}]'))
                              : 'Replied to a message',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: fg.withValues(alpha: 0.85))),
                      ),
                    ),
                  if (hasMedia)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: bodyText.isEmpty ? 4 : 6),
                      child: _mediaThumb(context),
                    ),
                  if (hasPlace)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: bodyText.isEmpty ? 4 : 6),
                      child: _placeCard(placeLat, placeLng),
                    ),
                  if (bodyText.isNotEmpty)
                    message.deleted
                        ? Text(bodyText,
                            style: TextStyle(
                                color: fg, fontStyle: FontStyle.italic))
                        : emojiOnly
                        ? Text(bodyText,
                            style: const TextStyle(fontSize: 44))
                        : (bodyText.length > 600 && !expanded)
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(bodyText,
                                      maxLines: 12,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: fg)),
                                  GestureDetector(
                                    onTap: onToggleExpand,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(top: 2),
                                      child: Text('Read more',
                                          style: TextStyle(
                                              color:
                                                  fg.withValues(alpha: 0.9),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12.5)),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinkedText(bodyText,
                                      style: TextStyle(color: fg)),
                                  if (bodyText.length > 600)
                                    GestureDetector(
                                      onTap: onToggleExpand,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text('Show less',
                                            style: TextStyle(
                                                color:
                                                    fg.withValues(alpha: 0.9),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5)),
                                      ),
                                    ),
                                ],
                              ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (starred)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.star,
                              size: 11, color: fg.withValues(alpha: 0.85)),
                        ),
                      if (message.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin,
                              size: 11, color: fg.withValues(alpha: 0.7)),
                        ),
                      if (message.editedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text('edited',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: fg.withValues(alpha: 0.7))),
                        ),
                      Text(shortAgo(message.createdAt),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: fg.withValues(alpha: 0.7))),
                      if (receipt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Icon(
                              receipt == 'Sent'
                                  ? Icons.check
                                  : Icons.done_all,
                              size: 13,
                              color: receipt == 'Seen'
                                  ? const Color(0xFF60A5FA)
                                  : fg.withValues(alpha: 0.7)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (reactions.isNotEmpty)
              GestureDetector(
                onTap: onTapReactions,
                child: Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(reactions.join('  '),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }
}

/// Sentinel row marking where unread messages begin.
const Object _unreadMarker = _UnreadMarker();

class _UnreadMarker {
  const _UnreadMarker();
}

/// A "Unread messages" divider shown above the first unread message.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
              child: Divider(color: scheme.primary.withValues(alpha: 0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Unread messages',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary)),
          ),
          Expanded(
              child: Divider(color: scheme.primary.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom viewer for a chat photo.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.provider});
  final ImageProvider provider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image(image: provider),
        ),
      ),
    );
  }
}

/// A centered day separator ("Today" / "Yesterday" / "Mar 5").
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.day});
  final DateTime day;

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = months[day.month - 1];
    return day.year == now.year ? '$m ${day.day}' : '$m ${day.day}, ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_label(),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ),
    );
  }
}

/// Tappable banner showing how many messages are pinned in the chat.
class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 16, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    count == 1 ? '1 pinned message' : '$count pinned messages',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Replying to …" preview shown above the composer.
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview(
      {required this.message,
      required this.senderName,
      required this.onCancel});
  final Message message;
  final String senderName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Replying to $senderName',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                  const SizedBox(height: 2),
                  Text(message.text ?? '[${message.type}]',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Cancel reply',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Search a user and start (or open) a direct conversation with them.
class _NewChatScreen extends StatefulWidget {
  const _NewChatScreen();

  @override
  State<_NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<_NewChatScreen> {
  final _search = TextEditingController();
  Future<List<PublicUser>>? _results;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = api.users.search(q));
  }

  Future<void> _start(PublicUser u) async {
    try {
      final conv = await api.messaging.startDirect(u.userId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conv, title: u.name),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: TextField(
          controller: _search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: const InputDecoration(
              hintText: 'Search people', border: InputBorder.none),
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: _run)],
      ),
      body: _results == null
          ? const CenteredMessage(
              message: 'Search for someone to message.', icon: Icons.search)
          : AsyncList<PublicUser>(
              future: _results!,
              emptyMessage: 'No people found.',
              emptyIcon: Icons.person_search_outlined,
              builder: (context, items) => ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final u = items[i];
                  return ListTile(
                    leading: Avatar(url: u.picture, name: u.name),
                    title: Text(u.name),
                    subtitle: u.username != null ? Text(u.handle) : null,
                    onTap: () => _start(u),
                  );
                },
              ),
            ),
    );
  }
}

/// Pick multiple people and an optional name to create a group conversation.
class _NewGroupScreen extends StatefulWidget {
  const _NewGroupScreen();

  @override
  State<_NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<_NewGroupScreen> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  Future<List<PublicUser>>? _results;
  final Map<String, PublicUser> _selected = {};
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  void _run() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = api.users.search(q));
  }

  void _toggle(PublicUser u) {
    setState(() {
      if (_selected.containsKey(u.userId)) {
        _selected.remove(u.userId);
      } else {
        _selected[u.userId] = u;
      }
    });
  }

  Future<void> _create() async {
    if (_selected.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final name = _name.text.trim();
      final conv = await api.messaging.createGroup(
        memberIds: _selected.keys.toList(),
        name: name.isEmpty ? null : name,
      );
      if (!mounted) return;
      final title = name.isNotEmpty
          ? name
          : _selected.values.map((u) => u.name).join(', ');
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conv, title: title),
      ));
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty || _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Group name (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final u in _selected.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar:
                            Avatar(url: u.picture, name: u.name, radius: 10),
                        label: Text(u.name),
                        onDeleted: () => _toggle(u),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: 'Search people to add',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward), onPressed: _run),
              ),
            ),
          ),
          Expanded(
            child: _results == null
                ? const CenteredMessage(
                    message: 'Search for people to add to the group.',
                    icon: Icons.group_add_outlined)
                : AsyncList<PublicUser>(
                    future: _results!,
                    emptyMessage: 'No people found.',
                    emptyIcon: Icons.person_search_outlined,
                    builder: (context, items) => ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final u = items[i];
                        final picked = _selected.containsKey(u.userId);
                        return ListTile(
                          leading: Avatar(url: u.picture, name: u.name),
                          title: Text(u.name),
                          subtitle: u.username != null ? Text(u.handle) : null,
                          trailing: Icon(picked
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked),
                          onTap: () => _toggle(u),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen map to drop a pin and return the chosen [LatLng].
class _LocationPickerScreen extends StatefulWidget {
  const _LocationPickerScreen();

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  LatLng _point = const LatLng(43.6532, -79.3832); // Toronto default

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Pick a location'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _point),
            child: const Text('Send'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _point,
              initialZoom: 12,
              onTap: (_, p) => setState(() => _point = p),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ca.okayspace.app',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: _point,
                  width: 44,
                  height: 44,
                  child: const Icon(Icons.location_pin,
                      color: Colors.red, size: 40),
                ),
              ]),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  child: Text('Tap the map to drop a pin',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
