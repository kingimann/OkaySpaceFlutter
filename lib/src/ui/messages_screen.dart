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

enum _ConvFilter { all, unread, groups, people }

enum _ConvSort { recent, unread, name }

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<ConversationView>> _conversations;
  final _search = TextEditingController();
  String _query = '';
  final _storage = const FlutterSecureStorage();

  // Local conversation organisation (persisted, no server support needed).
  Set<String> _pinned = {};
  Set<String> _archived = {};
  Set<String> _markedUnread = {};
  _ConvFilter _filter = _ConvFilter.all;
  _ConvSort _sort = _ConvSort.recent;
  bool _showArchived = false;
  int _unreadTotal = 0;
  // convId -> unsent draft text (read from per-chat draft keys).
  Map<String, String> _drafts = {};
  // convId -> local nickname overriding the displayed title.
  Map<String, String> _nicknames = {};

  static const _pinnedKey = 'okayspace.convos.pinned';
  static const _archivedKey = 'okayspace.convos.archived';
  static const _unreadKey = 'okayspace.convos.unread';
  static const _sortKey = 'okayspace.convos.sort';
  static const _nickKey = 'okayspace.convos.nicknames';
  static const _draftPrefix = 'okayspace.chat_draft.';

  @override
  void initState() {
    super.initState();
    _conversations = _load();
    _loadConvPrefs();
  }

  Future<List<ConversationView>> _load() async {
    final items = await api.messaging.conversations();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _unreadTotal = _totalUnread(items));
      });
    }
    return items;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadConvPrefs() async {
    Set<String> parse(String? s) =>
        (s ?? '').split('\n').where((e) => e.isNotEmpty).toSet();
    try {
      final p = await _storage.read(key: _pinnedKey);
      final a = await _storage.read(key: _archivedKey);
      final u = await _storage.read(key: _unreadKey);
      final s = await _storage.read(key: _sortKey);
      final nick = await _storage.read(key: _nickKey);
      final all = await _storage.readAll();
      if (!mounted) return;
      setState(() {
        _pinned = parse(p);
        _archived = parse(a);
        _markedUnread = parse(u);
        _sort = _ConvSort.values.firstWhere((e) => e.name == s,
            orElse: () => _ConvSort.recent);
        _drafts = {
          for (final e in all.entries)
            if (e.key.startsWith(_draftPrefix) && e.value.trim().isNotEmpty)
              e.key.substring(_draftPrefix.length): e.value,
        };
        if (nick != null && nick.isNotEmpty) {
          final decoded = jsonDecode(nick);
          if (decoded is Map) {
            _nicknames = {
              for (final e in decoded.entries) '${e.key}': '${e.value}'
            };
          }
        }
      });
    } catch (_) {/* ignore */}
  }

  void _setNickname(ConversationView c, String? name) {
    setState(() {
      if (name == null || name.trim().isEmpty) {
        _nicknames.remove(c.id);
      } else {
        _nicknames[c.id] = name.trim();
      }
    });
    _storage.write(key: _nickKey, value: jsonEncode(_nicknames)).ignore();
  }

  void _persist(String key, Set<String> set) =>
      _storage.write(key: key, value: set.join('\n')).ignore();

  void _togglePin(ConversationView c) {
    setState(() {
      if (!_pinned.remove(c.id)) _pinned.add(c.id);
    });
    _persist(_pinnedKey, _pinned);
  }

  void _toggleArchive(ConversationView c) {
    setState(() {
      if (!_archived.remove(c.id)) _archived.add(c.id);
    });
    _persist(_archivedKey, _archived);
  }

  void _markUnread(ConversationView c) {
    setState(() => _markedUnread.add(c.id));
    _persist(_unreadKey, _markedUnread);
  }

  void _clearUnreadMark(String id) {
    if (_markedUnread.remove(id)) _persist(_unreadKey, _markedUnread);
  }

  void _setSort(_ConvSort s) {
    setState(() => _sort = s);
    _storage.write(key: _sortKey, value: s.name).ignore();
  }

  Future<void> _reload() async {
    setState(() => _conversations = _load());
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
    final nick = _nicknames[c.id];
    if (nick != null && nick.isNotEmpty) return nick;
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  bool _isUnread(ConversationView c) =>
      c.unreadCount > 0 || _markedUnread.contains(c.id);

  int _totalUnread(List<ConversationView> items) => items
      .where((c) => !_archived.contains(c.id) && _isUnread(c))
      .length;

  /// Applies search, archive visibility, filter chip and sort order.
  List<ConversationView> _organise(List<ConversationView> items) {
    var list = items.where((c) {
      if (_showArchived != _archived.contains(c.id)) return false;
      if (_query.isNotEmpty) {
        final t = _title(c).toLowerCase();
        final p = (c.lastMessage?.text ?? '').toLowerCase();
        if (!t.contains(_query) && !p.contains(_query)) return false;
      }
      switch (_filter) {
        case _ConvFilter.unread:
          return _isUnread(c);
        case _ConvFilter.groups:
          return c.isGroup;
        case _ConvFilter.people:
          return !c.isGroup;
        case _ConvFilter.all:
          return true;
      }
    }).toList();
    int byRecent(ConversationView a, ConversationView b) {
      final ta = a.lastMessageAt;
      final tb = b.lastMessageAt;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    }

    int byCriteria(ConversationView a, ConversationView b) {
      switch (_sort) {
        case _ConvSort.unread:
          final ua = _isUnread(a) ? 0 : 1;
          final ub = _isUnread(b) ? 0 : 1;
          if (ua != ub) return ua - ub;
          return byRecent(a, b);
        case _ConvSort.name:
          return _title(a).toLowerCase().compareTo(_title(b).toLowerCase());
        case _ConvSort.recent:
          return byRecent(a, b);
      }
    }

    list.sort((a, b) {
      // Pinned conversations always float to the top (except in archived view).
      if (!_showArchived) {
        final pa = _pinned.contains(a.id) ? 0 : 1;
        final pb = _pinned.contains(b.id) ? 0 : 1;
        if (pa != pb) return pa - pb;
      }
      return byCriteria(a, b);
    });
    return list;
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
              leading: Icon(
                  _pinned.contains(c.id) ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(_pinned.contains(c.id) ? 'Unpin' : 'Pin to top'),
              onTap: () {
                Navigator.pop(context);
                _togglePin(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(
                  _nicknames.containsKey(c.id) ? 'Edit nickname' : 'Set nickname'),
              onTap: () async {
                Navigator.pop(context);
                final name = await promptText(context,
                    title: 'Nickname',
                    action: 'Save',
                    initial: _nicknames[c.id] ?? _title(c));
                if (name != null) _setNickname(c, name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined),
              title: const Text('Mark as read'),
              onTap: () async {
                Navigator.pop(context);
                _clearUnreadMark(c.id);
                try {
                  await api.messaging.markRead(c.id);
                } catch (_) {}
                if (mounted) _reload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_unread_outlined),
              title: const Text('Mark as unread'),
              onTap: () {
                Navigator.pop(context);
                _markUnread(c);
              },
            ),
            ListTile(
              leading: Icon(_archived.contains(c.id)
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              title: Text(
                  _archived.contains(c.id) ? 'Unarchive' : 'Archive'),
              onTap: () {
                Navigator.pop(context);
                _toggleArchive(c);
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
        title: Text(_showArchived
            ? 'Archived'
            : (_unreadTotal > 0 ? 'Messages ($_unreadTotal)' : 'Messages')),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            tooltip: _showArchived ? 'Back to inbox' : 'Archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          PopupMenuButton<_ConvSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: _setSort,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _ConvSort.recent, child: Text('Most recent')),
              PopupMenuItem(value: _ConvSort.unread, child: Text('Unread first')),
              PopupMenuItem(value: _ConvSort.name, child: Text('Name (A–Z)')),
            ],
          ),
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
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in _ConvFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(switch (f) {
                          _ConvFilter.all => 'All',
                          _ConvFilter.unread => 'Unread',
                          _ConvFilter.groups => 'Groups',
                          _ConvFilter.people => 'People',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
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
                    final filtered = _organise(items);
                    if (filtered.isEmpty) {
                      return CenteredMessage(
                          message: _showArchived
                              ? 'No archived conversations.'
                              : 'No matching conversations.',
                          icon: _showArchived
                              ? Icons.archive_outlined
                              : Icons.search_off);
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final title = _title(c);
                        return Dismissible(
                          key: ValueKey('conv-${c.id}'),
                          background: Container(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Icon(_archived.contains(c.id)
                                ? Icons.unarchive
                                : Icons.archive),
                          ),
                          secondaryBackground: Container(
                            color: Theme.of(context).colorScheme.errorContainer,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Icon(Icons.delete,
                                color: Theme.of(context).colorScheme.error),
                          ),
                          confirmDismiss: (dir) async {
                            if (dir == DismissDirection.startToEnd) {
                              _toggleArchive(c);
                              return false;
                            }
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                title: const Text('Delete conversation?'),
                                content: Text('Delete "$title"?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(d, false),
                                      child: const Text('Cancel')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(d, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              try {
                                await api.messaging.delete(c.id);
                                if (mounted) _reload();
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            }
                            return false;
                          },
                          child: _ConversationTile(
                            conversation: c,
                            title: title,
                            pinned: _pinned.contains(c.id),
                            forceUnread: _markedUnread.contains(c.id),
                            draft: _drafts[c.id],
                            onLongPress: () => _convActions(c),
                            onTap: () async {
                              _clearUnreadMark(c.id);
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    ChatScreen(conversation: c, title: title),
                              ));
                              if (mounted) _reload();
                            },
                          ),
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
    this.pinned = false,
    this.forceUnread = false,
    this.draft,
  });

  final ConversationView conversation;
  final String title;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Locally pinned to the top of the list.
  final bool pinned;

  /// Locally marked unread even when the server unread count is zero.
  final bool forceUnread;

  /// Unsent draft text for this conversation, shown in the preview if present.
  final String? draft;

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
    final unread = conversation.unreadCount > 0 || forceUnread;
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
      title: Row(
        children: [
          if (pinned)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.push_pin, size: 14, color: scheme.outline),
            ),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      subtitle: (draft != null && draft!.trim().isNotEmpty)
          ? Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'Draft: ',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.w600)),
                TextSpan(text: draft!.trim()),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.outline),
            )
          : Text(
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
          if (conversation.unreadCount > 0)
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
          else if (unread)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: scheme.primary, shape: BoxShape.circle),
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
  // New messages that arrived while scrolled away from the bottom.
  int _newSinceScroll = 0;
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
  // Show a timestamp under every message (per conversation, local).
  bool _showTimestamps = false;
  // Accent colour for your own bubbles (per conversation, local).
  Color? _bubbleColor;
  // Send on Enter vs. newline (shared, local).
  bool _sendOnEnter = true;
  // Live character count for the composer.
  int _charCount = 0;
  // Chat font family: 'default' | 'serif' | 'mono' (shared, local).
  String _fontFamily = 'default';
  // Square vs. rounded bubble corners (shared, local).
  bool _squareBubbles = false;
  // Compact message density (shared, local).
  bool _compact = false;
  // Emoji used by double-tap-to-react (shared, local).
  String _defaultReaction = '❤️';
  // Hide your own read receipts locally (per conversation).
  bool _hideReceipts = false;
  // Index of the currently highlighted in-chat search match.
  final List<String> _searchHits = [];
  int _searchPos = 0;
  // Rotating index for cycling through pinned messages from the banner.
  int _pinnedCycle = 0;

  String get _convId => widget.conversation.id;
  String get _draftKey => 'okayspace.chat_draft.$_convId';
  String get _starKey => 'okayspace.chat_starred.$_convId';
  String get _bgKey => 'okayspace.chat_bg.$_convId';
  String get _muteKey => 'okayspace.chat_mute.$_convId';
  String get _scaleKey => 'okayspace.chat_scale.$_convId';
  String get _tsKey => 'okayspace.chat_ts.$_convId';
  String get _bubbleKey => 'okayspace.chat_bubble.$_convId';
  String get _receiptKey => 'okayspace.chat_hidereceipts.$_convId';
  static const _quickKey = 'okayspace.chat_quickreplies';
  static const _enterKey = 'okayspace.chat_sendonenter';
  static const _fontKey = 'okayspace.chat_font';
  static const _cornerKey = 'okayspace.chat_square';
  static const _densityKey = 'okayspace.chat_compact';
  static const _reactKey = 'okayspace.chat_defaultreaction';

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
      if (show != _showJump) {
        setState(() {
          _showJump = show;
          if (!show) _newSinceScroll = 0;
        });
      }
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
      final ts = await _storage.read(key: _tsKey);
      final bubble = await _storage.read(key: _bubbleKey);
      final enter = await _storage.read(key: _enterKey);
      final font = await _storage.read(key: _fontKey);
      final square = await _storage.read(key: _cornerKey);
      final compact = await _storage.read(key: _densityKey);
      final react = await _storage.read(key: _reactKey);
      final hideR = await _storage.read(key: _receiptKey);
      if (!mounted) return;
      setState(() {
        final argb = int.tryParse(bg ?? '');
        _bgTint = (argb != null && argb != 0) ? Color(argb) : null;
        _muted = muted == '1';
        _textScale = double.tryParse(scale ?? '') ?? 1.0;
        if (quick != null && quick.isNotEmpty) {
          _quickReplies = quick.split('\n').where((s) => s.isNotEmpty).toList();
        }
        _showTimestamps = ts == '1';
        final bargb = int.tryParse(bubble ?? '');
        _bubbleColor = (bargb != null && bargb != 0) ? Color(bargb) : null;
        _sendOnEnter = enter != '0';
        _fontFamily = (font == 'serif' || font == 'mono') ? font! : 'default';
        _squareBubbles = square == '1';
        _compact = compact == '1';
        if (react != null && react.isNotEmpty) _defaultReaction = react;
        _hideReceipts = hideR == '1';
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

  void _toggleTimestamps() {
    setState(() => _showTimestamps = !_showTimestamps);
    _storage.write(key: _tsKey, value: _showTimestamps ? '1' : '0').ignore();
  }

  void _toggleSendOnEnter() {
    setState(() => _sendOnEnter = !_sendOnEnter);
    _storage.write(key: _enterKey, value: _sendOnEnter ? '1' : '0').ignore();
    showInfo(context,
        _sendOnEnter ? 'Enter now sends' : 'Enter now adds a new line');
  }

  void _toggleReceipts() {
    setState(() => _hideReceipts = !_hideReceipts);
    _storage.write(key: _receiptKey, value: _hideReceipts ? '1' : '0').ignore();
  }

  /// Bundled appearance options: font, bubble shape, density, default reaction.
  void _appearanceSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (c, setSheet) {
          void save(String key, String value, VoidCallback apply) {
            setState(apply);
            setSheet(() {});
            _storage.write(key: key, value: value).ignore();
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                    title: Text('Appearance',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Font'),
                      const Spacer(),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'default', label: Text('Aa')),
                          ButtonSegment(
                              value: 'serif',
                              label: Text('Aa',
                                  style: TextStyle(fontFamily: 'serif'))),
                          ButtonSegment(
                              value: 'mono',
                              label: Text('Aa',
                                  style: TextStyle(fontFamily: 'monospace'))),
                        ],
                        selected: {_fontFamily},
                        onSelectionChanged: (s) =>
                            save(_fontKey, s.first, () => _fontFamily = s.first),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Square bubbles'),
                  value: _squareBubbles,
                  onChanged: (v) => save(
                      _cornerKey, v ? '1' : '0', () => _squareBubbles = v),
                ),
                SwitchListTile(
                  title: const Text('Compact density'),
                  value: _compact,
                  onChanged: (v) =>
                      save(_densityKey, v ? '1' : '0', () => _compact = v),
                ),
                ListTile(
                  title: const Text('Double-tap reaction'),
                  trailing: Text(_defaultReaction,
                      style: const TextStyle(fontSize: 22)),
                  onTap: () async {
                    final picked = await showModalBottomSheet<String>(
                      context: c,
                      builder: (_) => SafeArea(
                        child: Wrap(
                          children: [
                            for (final e in const [
                              '❤️', '👍', '😂', '😮', '😢', '🙏', '🔥', '🎉'
                            ])
                              InkWell(
                                onTap: () => Navigator.pop(c, e),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(e,
                                      style: const TextStyle(fontSize: 28)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (picked != null) {
                      save(_reactKey, picked, () => _defaultReaction = picked);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _setBubbleColor(Color? c) {
    setState(() => _bubbleColor = c);
    if (c == null) {
      _storage.delete(key: _bubbleKey).ignore();
    } else {
      _storage.write(key: _bubbleKey, value: '${c.toARGB32()}').ignore();
    }
  }

  /// Own-bubble accent colour picker.
  void _chooseBubbleColor() {
    const swatches = <Color?>[
      null,
      Color(0xFF2563EB),
      Color(0xFF059669),
      Color(0xFFDC2626),
      Color(0xFF7C3AED),
      Color(0xFFDB2777),
      Color(0xFFEA580C),
      Color(0xFF0891B2),
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
              const Text('Bubble colour',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in swatches)
                    GestureDetector(
                      onTap: () {
                        _setBubbleColor(c);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: c ?? Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (_bubbleColor == c)
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).dividerColor,
                            width: (_bubbleColor == c) ? 3 : 1,
                          ),
                        ),
                        child: c == null
                            ? const Icon(Icons.refresh,
                                size: 20, color: Colors.white)
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

  /// Shows a grid of every photo shared in this conversation.
  void _sharedMedia() {
    ImageProvider? providerFor(Message m) {
      final media = m.media.first;
      if (media.url != null && media.url!.isNotEmpty) {
        return NetworkImage(media.url!);
      }
      if (media.base64 != null && media.base64!.isNotEmpty) {
        return MemoryImage(base64Decode(media.base64!));
      }
      return null;
    }

    final photos = _items
        .where((m) => !m.deleted && m.media.isNotEmpty && providerFor(m) != null)
        .toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: const OkayAppBar(title: Text('Shared media')),
        body: photos.isEmpty
            ? const CenteredMessage(
                message: 'No photos shared yet.',
                icon: Icons.photo_library_outlined)
            : GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                itemCount: photos.length,
                itemBuilder: (c, i) {
                  final provider = providerFor(photos[i])!;
                  return GestureDetector(
                    onTap: () => Navigator.of(c).push(MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => _ImageViewer(provider: provider))),
                    child: Image(
                        image: provider,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Colors.black12)),
                  );
                },
              ),
      ),
    ));
  }

  /// A small statistics sheet for the conversation.
  void _chatInfo() {
    final visible = _items.where((m) => !m.deleted).toList();
    final mine = visible.where(_isMine).length;
    final media =
        visible.where((m) => m.type == 'media' || m.media.isNotEmpty).length;
    DateTime? first;
    for (final m in visible) {
      if (first == null || m.createdAt.isBefore(first)) first = m.createdAt;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Chat info',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Messages loaded'),
              trailing: Text('${visible.length}'),
            ),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Sent by you'),
              trailing: Text('$mine'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photos'),
              trailing: Text('$media'),
            ),
            if (first != null)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Earliest loaded'),
                trailing: Text(first.toLocal().toString().split(' ').first),
              ),
          ],
        ),
      ),
    );
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

  /// Selects [from] and every newer (more recent) message.
  void _selectFrom(Message from) {
    setState(() {
      for (final m in _items) {
        if (!m.deleted && !m.createdAt.isBefore(from.createdAt)) {
          _selected.add(m.id);
        }
      }
    });
  }

  void _reportMessage(Message msg) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Report message'),
        content: const Text(
            'Report this message to moderators? Our team will review it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(c);
                showInfo(context, 'Reported. Thanks for letting us know.');
              },
              child: const Text('Report')),
        ],
      ),
    );
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
  void _onTyping(String v) {
    if (!_typingSent) {
      _typingSent = true;
      api.messaging.setPresence(_convId, 'typing').ignore();
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
    if ((v.isEmpty) != (_charCount == 0) || v.length != _charCount) {
      setState(() => _charCount = v.length);
    }
    _saveDraft();
    _updateMentions();
  }

  /// Inserts [emoji] at the composer's caret.
  void _insertEmoji(String emoji) => _insertText(emoji);

  /// Replaces the current selection (or inserts at the caret) with [str].
  void _insertText(String str) {
    final sel = _input.selection;
    final text = _input.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final next = text.replaceRange(start, end, str);
    setState(() {
      _input.text = next;
      _input.selection = TextSelection.collapsed(offset: start + str.length);
      _charCount = next.length;
    });
  }

  /// Wraps the current selection with [marker] on both sides (markdown style).
  void _wrapSelection(String marker) {
    final sel = _input.selection;
    final text = _input.text;
    if (!sel.isValid || sel.isCollapsed) {
      _insertText('$marker$marker');
      // Place the caret between the markers.
      final pos = _input.selection.start - marker.length;
      _input.selection = TextSelection.collapsed(offset: pos);
      return;
    }
    final selected = text.substring(sel.start, sel.end);
    final next = text.replaceRange(sel.start, sel.end, '$marker$selected$marker');
    setState(() {
      _input.text = next;
      _input.selection = TextSelection.collapsed(
          offset: sel.end + marker.length * 2);
      _charCount = next.length;
    });
  }

  /// Composer formatting menu: bold / italic / strikethrough / mention all.
  void _formatMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.format_bold),
              title: const Text('Bold'),
              onTap: () {
                Navigator.pop(context);
                _wrapSelection('**');
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_italic),
              title: const Text('Italic'),
              onTap: () {
                Navigator.pop(context);
                _wrapSelection('_');
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_strikethrough),
              title: const Text('Strikethrough'),
              onTap: () {
                Navigator.pop(context);
                _wrapSelection('~~');
              },
            ),
            if (widget.conversation.isGroup)
              ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('Mention everyone'),
                onTap: () {
                  Navigator.pop(context);
                  _insertText('@everyone ');
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Expands a few slash-command macros typed at the very start of a message.
  String _expandSlash(String text) {
    final t = text.trimRight();
    switch (t) {
      case '/shrug':
        return r'¯\_(ツ)_/¯';
      case '/tableflip':
        return '(╯°□°)╯︵ ┻━┻';
      case '/unflip':
        return '┬─┬ ノ( ゜-゜ノ)';
    }
    if (t.startsWith('/me ')) return '_${t.substring(4)}_';
    return text;
  }

  void _emojiPicker() {
    const emojis = [
      '😀', '😂', '🙂', '😍', '😘', '😎', '🤔', '😢', '😭', '😡',
      '👍', '👎', '👏', '🙏', '💪', '🔥', '🎉', '❤️', '💔', '⭐',
      '✅', '❌', '💯', '👀', '🙌', '🤝', '😅', '😴', '🥳', '😇',
      '🤗', '😉', '😋', '🤩', '😜', '🤯', '😱', '🥺', '😤', '🫶',
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 8,
          padding: const EdgeInsets.all(12),
          children: [
            for (final e in emojis)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.pop(context);
                  _insertEmoji(e);
                },
                child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 26))),
              ),
          ],
        ),
      ),
    );
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
      // Count messages that arrived while the user is scrolled up.
      final delta = msgs.length - _items.length;
      final grew = delta > 0 && _items.isNotEmpty;
      setState(() {
        if (grew && _showJump) _newSinceScroll += delta;
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
            bubbleColor: _bubbleColor,
            showTimestamp: _showTimestamps,
            fontFamily: _fontFamily,
            squareCorners: _squareBubbles,
            compact: _compact,
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
                    !_hideReceipts &&
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
                : () => _run(() => api.messaging
                    .reactToMessage(_convId, msg.id, _defaultReaction)),
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
  /// Jumps to the next pinned message each time the banner is tapped.
  void _cyclePinned() {
    final pinned = _items.where((m) => m.pinned && !m.deleted).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (pinned.isEmpty) return;
    final m = pinned[_pinnedCycle % pinned.length];
    setState(() => _pinnedCycle++);
    _jumpTo(m.id);
  }

  /// Steps through every message that @-mentions the current user.
  void _jumpToMentions() {
    final me = widget.conversation.members
        .where((u) => u.userId == currentUserId)
        .toList();
    final handle = me.isNotEmpty ? (me.first.username ?? me.first.name) : null;
    final hits = _items
        .where((m) {
          if (m.deleted || m.text == null) return false;
          final t = m.text!.toLowerCase();
          if (t.contains('@everyone')) return true;
          return handle != null && t.contains('@${handle.toLowerCase()}');
        })
        .map((m) => m.id)
        .toList();
    if (hits.isEmpty) {
      showInfo(context, 'No mentions of you');
      return;
    }
    _beginSearchBrowse(hits);
  }

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
    final text = _expandSlash(_input.text.trim());
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
    var mineOnly = false;
    var mediaOnly = false;
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
            final matches = _items
                .where((m) =>
                    !m.deleted &&
                    (q.isEmpty || (m.text ?? '').toLowerCase().contains(q)) &&
                    (!mineOnly || _isMine(m)) &&
                    (!mediaOnly || m.media.isNotEmpty))
                .toList()
                .reversed
                .toList();
            final active = q.isNotEmpty || mineOnly || mediaOnly;
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('From me'),
                        selected: mineOnly,
                        onSelected: (v) => setSheet(() => mineOnly = v),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('With media'),
                        selected: mediaOnly,
                        onSelected: (v) => setSheet(() => mediaOnly = v),
                      ),
                      const Spacer(),
                      if (active)
                        Text('${matches.length} result${matches.length == 1 ? '' : 's'}',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
                if (active && matches.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: TextButton.icon(
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Browse results in chat'),
                        onPressed: () {
                          Navigator.pop(context);
                          _beginSearchBrowse(
                              [for (final m in matches.reversed) m.id]);
                        },
                      ),
                    ),
                  ),
                if (active && matches.isEmpty)
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
                          leading: Icon(m.media.isNotEmpty
                              ? Icons.image_outlined
                              : Icons.chat_bubble_outline),
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
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  /// Starts in-chat result browsing with a prev/next navigator bar.
  void _beginSearchBrowse(List<String> ids) {
    if (ids.isEmpty) return;
    setState(() {
      _searchHits
        ..clear()
        ..addAll(ids);
      _searchPos = ids.length - 1; // start at the newest match
    });
    _jumpTo(_searchHits[_searchPos]);
  }

  void _searchStep(int delta) {
    if (_searchHits.isEmpty) return;
    final next = (_searchPos + delta).clamp(0, _searchHits.length - 1);
    setState(() => _searchPos = next);
    _jumpTo(_searchHits[_searchPos]);
  }

  void _endSearchBrowse() => setState(_searchHits.clear);

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
            if (msg.text != null && msg.text!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.format_quote),
                title: const Text('Quote'),
                onTap: () {
                  Navigator.pop(context);
                  final quoted =
                      msg.text!.split('\n').map((l) => '> $l').join('\n');
                  _insertText('$quoted\n');
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
            ListTile(
              leading: const Icon(Icons.playlist_add_check),
              title: const Text('Select from here'),
              onTap: () {
                Navigator.pop(context);
                _selectFrom(msg);
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
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () {
                Clipboard.setData(ClipboardData(
                    text:
                        'https://okayspace.ca/messages/$_convId?m=${msg.id}'));
                Navigator.pop(context);
                showInfo(context, 'Link copied');
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
            if (!mine && !msg.deleted)
              ListTile(
                leading: Icon(Icons.flag_outlined,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Report'),
                onTap: () {
                  Navigator.pop(context);
                  _reportMessage(msg);
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
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('Jump to oldest'),
              onTap: () {
                Navigator.pop(context);
                if (_scroll.hasClients) {
                  _scroll.animateTo(_scroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut);
                }
              },
            ),
            if (widget.conversation.isGroup)
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Jump to mentions'),
                onTap: () {
                  Navigator.pop(context);
                  _jumpToMentions();
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Shared media'),
              onTap: () {
                Navigator.pop(context);
                _sharedMedia();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Chat info'),
              onTap: () {
                Navigator.pop(context);
                _chatInfo();
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
              leading: const Icon(Icons.bubble_chart_outlined),
              title: const Text('Bubble colour'),
              onTap: () {
                Navigator.pop(context);
                _chooseBubbleColor();
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
              leading: const Icon(Icons.tune),
              title: const Text('Appearance'),
              onTap: () {
                Navigator.pop(context);
                _appearanceSheet();
              },
            ),
            if (!widget.conversation.isGroup)
              SwitchListTile(
                secondary: const Icon(Icons.done_all),
                title: const Text('Hide read receipts'),
                value: _hideReceipts,
                onChanged: (_) {
                  Navigator.pop(context);
                  _toggleReceipts();
                },
              ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule_outlined),
              title: const Text('Show timestamps'),
              value: _showTimestamps,
              onChanged: (_) {
                Navigator.pop(context);
                _toggleTimestamps();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.keyboard_return),
              title: const Text('Send on Enter'),
              value: _sendOnEnter,
              onChanged: (_) {
                Navigator.pop(context);
                _toggleSendOnEnter();
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
              onTap: _cyclePinned,
              onLongPress: _showPinned,
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
                    child: Badge(
                      isLabelVisible: _newSinceScroll > 0,
                      label: Text('$_newSinceScroll'),
                      child: FloatingActionButton.small(
                        heroTag: 'jumpToLatest',
                        onPressed: () {
                          setState(() => _newSinceScroll = 0);
                          _scroll.animateTo(0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut);
                        },
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_searchHits.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Text('${_searchPos + 1} of ${_searchHits.length}'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up),
                    tooltip: 'Older match',
                    onPressed:
                        _searchPos > 0 ? () => _searchStep(-1) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    tooltip: 'Newer match',
                    onPressed: _searchPos < _searchHits.length - 1
                        ? () => _searchStep(1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close search',
                    onPressed: _endSearchBrowse,
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
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    tooltip: 'Emoji',
                    onPressed: _sending ? null : _emojiPicker,
                  ),
                  IconButton(
                    icon: const Icon(Icons.text_format),
                    tooltip: 'Format',
                    onPressed: _sending ? null : _formatMenu,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: _sendOnEnter
                          ? TextInputType.text
                          : TextInputType.multiline,
                      textInputAction: _sendOnEnter
                          ? TextInputAction.send
                          : TextInputAction.newline,
                      onChanged: _onTyping,
                      onSubmitted: _sendOnEnter ? (_) => _send() : null,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                        suffixIcon: _charCount == 0
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_charCount > 200)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 4),
                                      child: Text('$_charCount',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline)),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    tooltip: 'Clear',
                                    onPressed: () => setState(() {
                                      _input.clear();
                                      _charCount = 0;
                                    }),
                                  ),
                                ],
                              ),
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
      this.bubbleColor,
      this.showTimestamp = false,
      this.fontFamily = 'default',
      this.squareCorners = false,
      this.compact = false,
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

  /// Accent colour for own bubbles (null = theme default).
  final Color? bubbleColor;

  /// When true, shows the exact time under every message.
  final bool showTimestamp;

  /// Chat font family: 'default' | 'serif' | 'mono'.
  final String fontFamily;

  /// Square vs. rounded bubble corners.
  final bool squareCorners;

  /// Compact message density (tighter padding/margins).
  final bool compact;

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

  static final _mdPattern =
      RegExp(r'\*\*(.+?)\*\*|~~(.+?)~~|_(.+?)_');

  bool _hasMarkdown(String s) => _mdPattern.hasMatch(s);

  /// Renders a subset of markdown (**bold**, _italic_, ~~strike~~) as spans.
  Widget _formattedBody(String text, TextStyle base) {
    final spans = <TextSpan>[];
    var idx = 0;
    for (final m in _mdPattern.allMatches(text)) {
      if (m.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, m.start)));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.bold)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
            text: m.group(2),
            style: const TextStyle(
                decoration: TextDecoration.lineThrough)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
            text: m.group(3),
            style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      idx = m.end;
    }
    if (idx < text.length) spans.add(TextSpan(text: text.substring(idx)));
    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// Formats a message time as "h:mm AM/PM" for the always-on timestamp mode.
  String _exactTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    final ap = l.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

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
            ? (bubbleColor ??
                HSLColor.fromColor(scheme.primary).withLightness(0.22).toColor())
            : scheme.surfaceContainerHighest;
    final fg = mine ? OkayColors.textPrimary : scheme.onSurface;
    final radius = Radius.circular(squareCorners ? 6 : 18);
    final tailRadius = Radius.circular(squareCorners ? 6 : 4);
    final fontFam = fontFamily == 'serif'
        ? 'serif'
        : (fontFamily == 'mono' ? 'monospace' : null);
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
              margin: EdgeInsets.only(top: compact ? 1 : 3),
              padding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: compact ? 6 : 9),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: radius,
                  topRight: radius,
                  bottomLeft: mine ? radius : tailRadius,
                  bottomRight: mine ? tailRadius : radius,
                ),
                border: highlight
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontFamily: fontFam),
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
                                  _hasMarkdown(bodyText)
                                      ? _formattedBody(
                                          bodyText, TextStyle(color: fg))
                                      : LinkedText(bodyText,
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
                      Text(
                          showTimestamp
                              ? _exactTime(message.createdAt)
                              : shortAgo(message.createdAt),
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
  const _PinnedBanner(
      {required this.count, required this.onTap, this.onLongPress});
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
