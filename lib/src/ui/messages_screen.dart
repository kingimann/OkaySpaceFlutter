import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../okayspace_api.dart';
import '../core/device_location.dart';
import '../core/foursquare_api.dart';
import '../core/mapbox_api.dart';
import 'games/three_game.dart';
import 'call_screen.dart';
import '../core/update_checker.dart';
import 'common.dart';
import 'linked_text.dart';

/// Label for a call-event message (missed / declined / ended-with-duration).
String _callLabel(Message m) {
  final status = '${m.raw['call_status'] ?? 'ended'}';
  final video = m.raw['call_video'] == true;
  final icon = video ? '📹' : '📞';
  if (status == 'missed') return '$icon Missed ${video ? 'video ' : ''}call';
  if (status == 'declined') return '$icon Call declined';
  final ms = (m.raw['call_duration_ms'] as num?)?.toInt() ?? 0;
  if (ms >= 1000) {
    final s = ms ~/ 1000;
    final mm = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$icon Call · $mm:$ss';
  }
  return '$icon Call ended';
}

/// Safely renders a custom-emoji image from a base64 (or data-URI) string,
/// returning [fallback] if the data is missing or malformed (base64Decode
/// throws synchronously, before Image.memory's errorBuilder can catch it).
Widget customEmojiImage(String b64, double size, Widget fallback) {
  try {
    final comma = b64.indexOf(',');
    final data =
        (b64.startsWith('data:') && comma != -1) ? b64.substring(comma + 1) : b64;
    return Image.memory(base64Decode(data),
        width: size, height: size, errorBuilder: (_, __, ___) => fallback);
  } catch (_) {
    return fallback;
  }
}

/// Safely builds a [MemoryImage] from a base64 (or data-URI) string, returning
/// null if the data is malformed (avoids a synchronous base64Decode crash).
ImageProvider? memoryImageFromB64(String b64) {
  try {
    final comma = b64.indexOf(',');
    final data =
        (b64.startsWith('data:') && comma != -1) ? b64.substring(comma + 1) : b64;
    return MemoryImage(base64Decode(data));
  } catch (_) {
    return null;
  }
}

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
      'post' => '📄 Shared a post',
      'place' => '📍 Location',
      'live_location' => '📍 Live location',
      'game' => '🎮 ${_gameMeta('${m.raw['game_type'] ?? 'tictactoe'}').$1}',
      'money' || 'tip' => '💸 Payment',
      'poll' => '📊 Poll',
      'file' => '📎 File',
      'contact' => '👤 Contact',
      'form' => '📋 Form',
      'call' => m.raw['call_status'] == 'missed' ? '📞 Missed call' : '📞 Call',
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
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (conversation.listingTitle != null &&
              conversation.listingTitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sell_outlined,
                        size: 11, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 90),
                      child: Text(conversation.listingTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: scheme.onTertiaryContainer)),
                    ),
                  ],
                ),
              ),
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
  // Live presence of the other participant(s): polled while the chat is open.
  Timer? _presencePoll;
  bool _otherTyping = false;
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
  // Custom emoji: shortcode -> base64 image, rendered inline as :shortcode:.
  Map<String, String> _customEmojis = const {};
  // Tap-to-reveal: the message whose exact time + status is shown (Messenger-style).
  String? _revealedId;
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
  // Server-side read-receipts setting (whether others see your reads).
  late bool _receiptsEnabled = widget.conversation.receiptsEnabled;
  // Server chat theme (one of the 8 Messenger themes).
  late String _chatTheme = widget.conversation.theme ?? 'default';
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
    _loadCustomEmojis();
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
    // Faster, lightweight presence poll so the "typing…" indicator is timely
    // (the backend's typing window is ~6s).
    _refreshPresence();
    _presencePoll = Timer.periodic(
        const Duration(seconds: 3), (_) => _refreshPresence());
  }

  Future<void> _refreshPresence() async {
    try {
      final p = await api.messaging.presence(_convId);
      final typing = p['typing'] == true;
      if (mounted && typing != _otherTyping) {
        setState(() => _otherTyping = typing);
      }
    } catch (_) {/* presence is best-effort */}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _presencePoll?.cancel();
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    _draftTimer?.cancel();
    for (final t in _liveUpdaters.values) {
      t.cancel();
    }
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

  Future<void> _loadCustomEmojis() async {
    try {
      final list = await api.messaging.customEmojis();
      if (!mounted) return;
      setState(() => _customEmojis = {
            for (final e in list)
              if ('${e['shortcode'] ?? ''}'.isNotEmpty &&
                  '${e['image_base64'] ?? ''}'.isNotEmpty)
                '${e['shortcode']}': '${e['image_base64']}',
          });
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
      if (!mounted) return;
      setState(() {
        // Start from the server chat theme, then let any local override win.
        final themeColors = _chatThemes[_chatTheme] ?? (null, null);
        _bgTint = themeColors.$1;
        _bubbleColor = themeColors.$2;
        final argb = int.tryParse(bg ?? '');
        if (argb != null && argb != 0) _bgTint = Color(argb);
        _muted = muted == '1';
        _textScale = double.tryParse(scale ?? '') ?? 1.0;
        if (quick != null && quick.isNotEmpty) {
          _quickReplies = quick.split('\n').where((s) => s.isNotEmpty).toList();
        }
        _showTimestamps = ts == '1';
        final bargb = int.tryParse(bubble ?? '');
        if (bargb != null && bargb != 0) _bubbleColor = Color(bargb);
        _sendOnEnter = enter != '0';
        _fontFamily = (font == 'serif' || font == 'mono') ? font! : 'default';
        _squareBubbles = square == '1';
        _compact = compact == '1';
        if (react != null && react.isNotEmpty) _defaultReaction = react;
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

  Future<void> _toggleReadReceipts(bool enabled) async {
    setState(() => _receiptsEnabled = enabled);
    try {
      await api.messaging.setReadReceipts(_convId, enabled);
    } catch (e) {
      if (mounted) {
        setState(() => _receiptsEnabled = !enabled);
        showError(context, e);
      }
    }
  }

  /// The 8 Messenger-style chat themes → (background tint, own-bubble colour).
  static const _chatThemes = <String, (Color?, Color?)>{
    'default': (null, null),
    'ocean': (Color(0xFFE3F2FD), Color(0xFF2563EB)),
    'sunset': (Color(0xFFFFF1E6), Color(0xFFF97316)),
    'forest': (Color(0xFFE8F5E9), Color(0xFF16A34A)),
    'grape': (Color(0xFFF3E8FF), Color(0xFF7C3AED)),
    'rose': (Color(0xFFFFE4EC), Color(0xFFE11D48)),
    'midnight': (Color(0xFF1E293B), Color(0xFF6366F1)),
    'mono': (Color(0xFFECEFF1), Color(0xFF374151)),
  };

  void _chooseChatTheme() {
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
              const Text('Chat theme',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in _chatThemes.entries)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _applyChatTheme(e.key);
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: e.value.$2 ??
                                  Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _chatTheme == e.key
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(e.key, style: const TextStyle(fontSize: 10)),
                        ],
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

  void _applyChatTheme(String theme) {
    final colors = _chatThemes[theme] ?? (null, null);
    setState(() {
      _chatTheme = theme;
      _bgTint = colors.$1;
      _bubbleColor = colors.$2;
    });
    api.messaging.setTheme(_convId, theme).ignore();
  }

  /// Assembles a transcript from loaded messages and shows an AI summary.
  Future<void> _summarizeChat() async {
    final lines = <String>[];
    for (final m in _items) {
      if (m.deleted || m.text == null || m.text!.isEmpty) continue;
      final who = _isMine(m) ? 'You' : _senderName(m.senderId);
      lines.add('$who: ${m.text}');
    }
    if (lines.isEmpty) {
      showInfo(context, 'Nothing to summarize yet');
      return;
    }
    final transcript = lines.length > 150
        ? lines.sublist(lines.length - 150).join('\n')
        : lines.join('\n');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final summary = await api.messaging.summarize(_convId, transcript);
      if (!mounted) return;
      Navigator.pop(context); // close spinner
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Chat summary',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
                const SizedBox(height: 12),
                Text(summary.isEmpty ? 'No summary available.' : summary),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showError(context, e);
      }
    }
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

  /// Shows the shared Media / Files / Links gallery for this conversation.
  void _sharedMedia() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SharedGalleryScreen(
          messages: _items.where((m) => !m.deleted).toList()),
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
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            if (_customEmojis.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text('Custom',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
              Wrap(
                children: [
                  for (final e in _customEmojis.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(context);
                        _insertText(':${e.key}:');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: customEmojiImage(e.value, 28, Text(':${e.key}:')),
                      ),
                    ),
                ],
              ),
              const Divider(height: 16),
            ],
            Wrap(
              children: [
                for (final e in emojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.pop(context);
                      _insertEmoji(e);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
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
    // Encryption notice at the very top of the thread (reverse list → last row).
    if (messagesEncrypted.value) rows.add(_encBanner);

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
          if (identical(row, _encBanner)) return const _EncryptionNotice();
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
            showTimestamp: _showTimestamps || _revealedId == msg.id,
            fontFamily: _fontFamily,
            customEmojis: _customEmojis,
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
            onVotePoll: msg.type == 'poll' && !msg.deleted
                ? (i) => _run(() => api.messaging.votePoll(_convId, msg.id, i))
                : null,
            onStopLive: msg.type == 'live_location' && mine
                ? () => _stopLiveShare('${msg.raw['live_share_id'] ?? ''}')
                : null,
            otherUserId: widget.conversation.otherUser?.userId,
            senderName:
                (isGroup && !mine && !msg.deleted) ? _senderName(msg.senderId) : null,
            receipt: (!isGroup &&
                    mine &&
                    _receiptsEnabled &&
                    (msg.id == lastMineId || _revealedId == msg.id))
                ? _receipt(msg)
                : null,
            // In selection mode, a tap toggles selection instead of opening.
            onTap: _selectionMode
                ? () => _toggleSelect(msg)
                : (msg.deleted
                    ? null
                    : () => setState(() =>
                        _revealedId = _revealedId == msg.id ? null : msg.id)),
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

  /// Schedules the composer text to send at a chosen future time.
  Future<void> _scheduleMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      showInfo(context, 'Type a message to schedule');
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 10))),
    );
    if (time == null || !mounted) return;
    final at = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    if (!at.isAfter(now.add(const Duration(minutes: 1)))) {
      showInfo(context, 'Pick a time at least a minute from now');
      return;
    }
    try {
      await api.messaging.scheduleMessage(_convId, text, at);
      if (mounted) {
        _input.clear();
        _clearDraft();
        showInfo(context, 'Message scheduled');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Lists pending scheduled messages with a cancel action.
  void _showScheduled() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => FutureBuilder<List<Map<String, dynamic>>>(
        future: api.messaging.scheduledMessages(_convId),
        builder: (sheetCtx, snap) {
          final items = snap.data ?? const [];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                    title: Text('Scheduled messages',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                if (snap.connectionState == ConnectionState.waiting)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator())
                else if (items.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No scheduled messages.'))
                else
                  for (final s in items)
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text('${s['body'] ?? s['text'] ?? ''}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text((s['send_at'] ?? '')
                          .toString()
                          .replaceFirst('T', ' ')
                          .split('.')
                          .first),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final id = '${s['id'] ?? s['scheduled_id'] ?? ''}';
                          if (id.isEmpty) return;
                          try {
                            await api.messaging.cancelScheduled(_convId, id);
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                            if (mounted) showInfo(context, 'Cancelled');
                          } catch (e) {
                            if (mounted) showError(context, e);
                          }
                        },
                      ),
                    ),
              ],
            ),
          );
        },
      ),
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

  /// Attachment chooser: a compact icon grid so every option is visible at
  /// once (no scrolling), grouped into what you send vs. how you compose.
  void _attachMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _attachSectionLabel('Attach'),
              Wrap(
                children: [
                  _attachTile(Icons.photo_outlined, 'Photo', _attachImage),
                  _attachTile(Icons.attach_file, 'File', _attachFile),
                  _attachTile(
                      Icons.place_outlined, 'Location', _attachLocation),
                  _attachTile(Icons.poll_outlined, 'Poll', _attachPoll),
                  _attachTile(Icons.attach_money, 'Tip', _attachTip),
                ],
              ),
              const SizedBox(height: 8),
              _attachSectionLabel('Compose'),
              Wrap(
                children: [
                  _attachTile(
                      Icons.emoji_emotions_outlined, 'Emoji', _emojiPicker),
                  _attachTile(Icons.text_format, 'Format', _formatMenu),
                  _attachTile(Icons.schedule_send_outlined, 'Schedule',
                      _scheduleMessage),
                ],
              ),
              // Games are one-on-one only.
              if (!widget.conversation.isGroup) ...[
                const SizedBox(height: 8),
                _attachSectionLabel('Play'),
                Wrap(
                  children: [
                    _attachTile(Icons.sports_esports_outlined, 'Games',
                        _openGamesList),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachSectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.outline)),
      );

  /// One option in the attachment grid: a circular icon over a label. Closes
  /// the sheet, then runs [action].
  Widget _attachTile(IconData icon, String label, VoidCallback action) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 80,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(context);
          action();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  /// Composes and sends a poll message (question + 2–6 options).
  Future<void> _attachPoll() async {
    final result = await showDialog<(String, List<String>)>(
      context: context,
      builder: (_) => const _PollComposer(),
    );
    if (result == null || !mounted) return;
    final (question, options) = result;
    try {
      await api.messaging.send(
          _convId,
          MessageCreate(
              type: 'poll', pollQuestion: question, pollOptions: options));
      await _fetch(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Starts an in-chat game of [type] and drops its playable card.
  /// A quick chooser before starting a game: opponent (friend/computer) for the
  /// two-player games when there's a partner, and difficulty for CPU/arcade.
  /// The full catalogue of games, in display order: (type, one-line blurb).
  static const _gameCatalog = <(String, String)>[
    ('tictactoe', 'Three in a row'),
    ('connect4', 'Drop discs, four in a row'),
    ('chess', 'The classic'),
    ('checkers', 'Jump and capture'),
    ('dotsboxes', 'Claim the most boxes'),
    ('blackjack', 'Beat the dealer to 21'),
    ('poker', 'Five-card draw'),
    ('pong', 'Paddle arcade'),
    ('snake', 'Eat and grow'),
  ];

  /// Opens a scrollable list of every game; tapping one starts it.
  void _openGamesList() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Games',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final g in _gameCatalog)
                    _gameListTile(ctx, g.$1, g.$2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameListTile(BuildContext ctx, String type, String blurb) {
    final (label, icon, color) = _gameMeta(type);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      subtitle: Text(blurb),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.pop(ctx);
        _startGameFlow(type);
      },
    );
  }

  Future<void> _startGameFlow(String type) async {
    const twoPlayer = {'tictactoe', 'chess', 'checkers', 'connect4', 'dotsboxes'};
    const arcade = {'pong', 'snake'};
    final hasPartner =
        !widget.conversation.isGroup && widget.conversation.otherUser != null;
    var vsCpu = !hasPartner; // notes-to-self has no partner → computer
    if (twoPlayer.contains(type) && hasPartner) {
      final opp = await _gamePick(context, 'Play against', const [
        ('A friend', 'friend'),
        ('The computer', 'cpu'),
      ]);
      if (opp == null) return;
      vsCpu = opp == 'cpu';
    }
    if (!mounted) return;
    var difficulty = 'medium';
    if (arcade.contains(type) || (twoPlayer.contains(type) && vsCpu)) {
      final d = await _gamePick(context, 'Difficulty', const [
        ('Easy', 'easy'),
        ('Medium', 'medium'),
        ('Hard', 'hard'),
      ]);
      if (d == null) return;
      difficulty = d;
    }
    if (!mounted) return;
    // Wager points (arcade games can't be bet on).
    var bet = 0;
    if (!arcade.contains(type)) {
      final b = await _betPick();
      if (b == null) return;       // cancelled
      bet = b;
    }
    await _startGame(type, difficulty: difficulty, vsCpu: vsCpu, bet: bet);
  }

  /// Lets the player wager points on the game. Returns the stake (0 = no bet)
  /// or null if cancelled. Only offers amounts the player can afford.
  Future<int?> _betPick() async {
    int points = 0;
    try {
      points = (await api.auth.me()).points;
    } catch (_) {/* fall back to no betting */}
    if (!mounted) return 0;
    if (points < 10) return 0;     // nothing meaningful to bet
    final amounts = [10, 25, 50, 100, 250].where((a) => a <= points).toList();
    return showModalBottomSheet<int>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Wager points',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Winner takes the pot · you have $points pts',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(sheetCtx).colorScheme.outline)),
            ),
          ),
          ListTile(
              leading: const Icon(Icons.block),
              title: const Text('No bet'),
              onTap: () => Navigator.pop(sheetCtx, 0)),
          for (final a in amounts)
            ListTile(
                leading: const Icon(Icons.toll_outlined),
                title: Text('$a pts'),
                onTap: () => Navigator.pop(sheetCtx, a)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<String?> _gamePick(
          BuildContext ctx, String title, List<(String, String)> opts) =>
      showModalBottomSheet<String>(
        context: ctx,
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            for (final o in opts)
              ListTile(
                  title: Text(o.$1),
                  onTap: () => Navigator.pop(ctx, o.$2)),
            const SizedBox(height: 8),
          ]),
        ),
      );

  Future<void> _startGame(String type,
      {String difficulty = 'medium', bool vsCpu = false, int bet = 0}) async {
    setState(() => _sending = true);
    try {
      await api.messaging.createGame(_convId,
          type: type, difficulty: difficulty, vsCpu: vsCpu, bet: bet);
      await _fetch(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Sends a tip (money) inside the conversation.
  Future<void> _attachTip() async {
    final amountText = await promptText(context,
        title: 'Send a tip', hint: 'Amount', action: 'Send');
    final amount = num.tryParse(amountText ?? '');
    if (amount == null || amount <= 0) return;
    try {
      await api.messaging
          .send(_convId, MessageCreate(type: 'tip', amount: amount));
      await _fetch(silent: true);
      _scrollToBottom();
      if (mounted) showInfo(context, 'Tip sent 🎉');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Picks a point on a map and sends it as a location message, or starts a
  /// live-location share.
  Future<void> _attachLocation() async {
    final picked = await Navigator.of(context).push<_LocationResult>(
      MaterialPageRoute(builder: (_) => const _LocationPickerScreen()),
    );
    if (picked == null || !mounted) return;
    if (picked.isLive) {
      await _startLiveShare(picked.liveMinutes!, picked.point);
      return;
    }
    setState(() => _sending = true);
    try {
      await api.messaging.send(
        _convId,
        MessageCreate(
          type: 'place',
          placeName: picked.name,
          placeLatitude: picked.point.latitude,
          placeLongitude: picked.point.longitude,
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

  /// Active live-location updaters, keyed by share id, so they can be cancelled
  /// on stop or when the screen is disposed.
  final Map<String, Timer> _liveUpdaters = {};

  /// Begins a live-location share and pumps the device's position to the
  /// backend until it expires or is stopped.
  Future<void> _startLiveShare(int minutes, LatLng initial) async {
    setState(() => _sending = true);
    try {
      final msg = await api.messaging
          .startLiveLocation(_convId, minutes, initial.latitude, initial.longitude);
      final shareId = '${msg.raw['live_share_id'] ?? ''}';
      if (shareId.isNotEmpty) {
        final expiry = DateTime.now().add(Duration(minutes: minutes));
        // Push a fresh fix every 15s until the share's time is up.
        _liveUpdaters[shareId] = Timer.periodic(
            const Duration(seconds: 15), (t) async {
          if (!mounted || DateTime.now().isAfter(expiry)) {
            t.cancel();
            _liveUpdaters.remove(shareId);
            return;
          }
          final fix = await currentFix();
          if (fix == null) return;
          try {
            await api.messaging
                .updateLiveLocation(shareId, fix.point.latitude, fix.point.longitude);
          } catch (_) {
            // 410 (ended/expired) or transient — stop pushing on a hard stop.
            t.cancel();
            _liveUpdaters.remove(shareId);
          }
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

  /// Stops a live-location share (the sharer tapped "Stop").
  Future<void> _stopLiveShare(String shareId) async {
    _liveUpdaters.remove(shareId)?.cancel();
    try {
      await api.messaging.stopLiveLocation(shareId);
      await _fetch(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
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
  /// Picks a file and sends it as a file message (capped at ~6 MB).
  Future<void> _attachFile() async {
    if (_sending) return;
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.length > 6 * 1024 * 1024) {
      if (mounted) showInfo(context, 'File is too large (max 6 MB)');
      return;
    }
    final replyTo = _replyTo?.id;
    setState(() => _sending = true);
    try {
      await api.messaging.send(
        _convId,
        MessageCreate(
          type: 'file',
          fileBase64: base64Encode(bytes),
          fileName: file.name,
          fileSize: bytes.length,
          fileMime: file.extension != null ? 'application/${file.extension}' : null,
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

  /// Conversation options — a full page (not a sheet) since the list is long.
  /// Actions close the page first, then run; the in-place toggles stay put.
  void _conversationMenu() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: const OkayAppBar(title: Text('Chat options')),
        body: SafeArea(
          child: StatefulBuilder(
            builder: (menuCtx, setLocal) => ListView(
              children: [
                _optionsHeader('Find'),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Starred messages'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _showStarred();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_send_outlined),
                  title: const Text('Scheduled messages'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _showScheduled();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Jump to date'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _jumpToDate();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.vertical_align_top),
                  title: const Text('Jump to oldest'),
                  onTap: () {
                    Navigator.pop(menuCtx);
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
                      Navigator.pop(menuCtx);
                      _jumpToMentions();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Shared media'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _sharedMedia();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Chat info'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _chatInfo();
                  },
                ),
                const Divider(height: 8),
                _optionsHeader('Notifications & privacy'),
                ListTile(
                  leading: Icon(_muted
                      ? Icons.notifications_off
                      : Icons.notifications_none),
                  title: Text(
                      _muted ? 'Unmute notifications' : 'Mute notifications'),
                  onTap: () {
                    _toggleMute();
                    setLocal(() {});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.done_all),
                  title: const Text('Read receipts'),
                  subtitle: const Text('Let others see when you’ve read'),
                  value: _receiptsEnabled,
                  onChanged: (v) {
                    _toggleReadReceipts(v);
                    setLocal(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Disappearing messages'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _disappearing();
                  },
                ),
                const Divider(height: 8),
                _optionsHeader('Appearance'),
                ListTile(
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: const Text('Chat wallpaper'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _chooseWallpaper();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bubble_chart_outlined),
                  title: const Text('Bubble colour'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _chooseBubbleColor();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('Text size'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _chooseTextSize();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Chat theme'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _chooseChatTheme();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Appearance'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _appearanceSheet();
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.schedule_outlined),
                  title: const Text('Show timestamps'),
                  value: _showTimestamps,
                  onChanged: (_) {
                    _toggleTimestamps();
                    setLocal(() {});
                  },
                ),
                const Divider(height: 8),
                _optionsHeader('Composing'),
                SwitchListTile(
                  secondary: const Icon(Icons.keyboard_return),
                  title: const Text('Send on Enter'),
                  value: _sendOnEnter,
                  onChanged: (_) {
                    _toggleSendOnEnter();
                    setLocal(() {});
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.quickreply_outlined),
                  title: const Text('Quick replies'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _manageQuickReplies();
                  },
                ),
                const Divider(height: 8),
                _optionsHeader('More'),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Summarize chat (AI)'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _summarizeChat();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Export conversation'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _exportChat();
                  },
                ),
                if (widget.conversation.isGroup)
                  ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: const Text('Rename group'),
                    onTap: () async {
                      Navigator.pop(menuCtx);
                      final name = await promptText(context,
                          title: 'Group name',
                          action: 'Save',
                          initial: _chatTitle);
                      if (name == null) return;
                      await _run(
                          () =>
                              api.messaging.updateGroup(_convId, {'name': name}),
                          'Renamed');
                      if (mounted) setState(() => _chatTitle = name);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Leave conversation'),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _run(() => api.messaging.leave(_convId),
                        'Left conversation').then((_) {
                      if (mounted) Navigator.pop(context);
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  title: Text('Delete conversation',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  onTap: () {
                    Navigator.pop(menuCtx);
                    _run(() => api.messaging.delete(_convId), 'Deleted')
                        .then((_) {
                      if (mounted) Navigator.pop(context);
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  /// Small section heading inside the chat-options page.
  Widget _optionsHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Theme.of(context).colorScheme.primary)),
      );

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
                      // Encrypted-chat indicator (when the server encrypts
                      // message content at rest).
                      ValueListenableBuilder<bool>(
                        valueListenable: messagesEncrypted,
                        builder: (context, on, _) => on
                            ? const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.lock,
                                    size: 13, color: Color(0xFF22C55E)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  if (_otherTyping)
                    Text('typing…',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.primary))
                  else if (other != null)
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
                  // One "+" holds every compose action (photo, file, poll,
                  // tip, emoji, formatting, schedule).
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add',
                    onPressed: _sending ? null : _attachMenu,
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
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        isDense: true,
                        counterText: '',
                        contentPadding: const EdgeInsets.fromLTRB(
                            16, 10, 4, 10),
                        // The send key lives inside the field.
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_charCount > 200)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Text('$_charCount',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline)),
                              ),
                            IconButton(
                              onPressed: _sending ? null : _send,
                              tooltip: 'Send',
                              icon: Icon(Icons.send,
                                  color: _charCount == 0
                                      ? Theme.of(context).colorScheme.outline
                                      : Theme.of(context).colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
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
      this.customEmojis = const {},
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
      this.onVotePoll,
      this.onStopLive,
      this.otherUserId,
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

  /// Custom emoji map (shortcode -> base64), rendered inline for `:shortcode:`.
  final Map<String, String> customEmojis;

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

  /// Casts a vote on this poll message (option index).
  final void Function(int optionIndex)? onVotePoll;

  /// Sharer-only: stop an in-progress live-location share.
  final VoidCallback? onStopLive;

  /// The DM partner's id (for arcade high-score comparison); null in groups.
  final String? otherUserId;

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
  static final _emojiToken = RegExp(r':(\w+):');

  bool _hasCustomEmoji(String s) =>
      customEmojis.isNotEmpty &&
      _emojiToken.allMatches(s).any((m) => customEmojis.containsKey(m.group(1)));

  /// Renders text with `:shortcode:` custom emojis substituted as inline images.
  Widget _emojiText(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    var idx = 0;
    for (final m in _emojiToken.allMatches(text)) {
      final code = m.group(1)!;
      final b64 = customEmojis[code];
      if (b64 == null) continue;
      if (m.start > idx) spans.add(TextSpan(text: text.substring(idx, m.start)));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: customEmojiImage(b64, 20, Text(':$code:', style: base)),
        ),
      ));
      idx = m.end;
    }
    if (idx < text.length) spans.add(TextSpan(text: text.substring(idx)));
    return Text.rich(TextSpan(style: base, children: spans));
  }

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
  /// A poll bubble: the question + its options (read-only preview).
  Widget _pollCard(Color fg) {
    final question = '${message.raw['poll_question'] ?? 'Poll'}';
    final opts = message.raw['poll_options'];
    final options = opts is List ? opts.map((e) => '$e').toList() : <String>[];

    // Vote counts: list of ints, or a map of index/option -> count.
    final votesRaw = message.raw['poll_votes'] ??
        message.raw['votes'] ??
        message.raw['poll_results'];
    int toInt(Object? v) =>
        v is num ? v.toInt() : (v is Map ? toInt(v['count']) : int.tryParse('$v') ?? 0);
    final counts = List<int>.filled(options.length, 0);
    if (votesRaw is List) {
      for (var i = 0; i < votesRaw.length && i < counts.length; i++) {
        counts[i] = toInt(votesRaw[i]);
      }
    } else if (votesRaw is Map) {
      votesRaw.forEach((k, v) {
        final i = int.tryParse('$k');
        if (i != null && i >= 0 && i < counts.length) counts[i] = toInt(v);
      });
    }
    final total = counts.fold<int>(0, (a, b) => a + b);
    final myVoteRaw =
        message.raw['poll_voted_index'] ?? message.raw['my_vote'] ?? message.raw['voted'];
    final myVote = myVoteRaw is num ? myVoteRaw.toInt() : int.tryParse('$myVoteRaw');
    final voted = myVote != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.poll_outlined, size: 18, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(question,
                style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < options.length; i++)
          GestureDetector(
            onTap: onVotePoll == null ? null : () => onVotePoll!(i),
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                border: Border.all(
                    color: fg.withValues(alpha: myVote == i ? 0.9 : 0.4),
                    width: myVote == i ? 1.5 : 1),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (voted && total > 0)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (counts[i] / total).clamp(0.0, 1.0),
                        child: ColoredBox(color: fg.withValues(alpha: 0.15)),
                      ),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(options[i], style: TextStyle(color: fg))),
                        if (voted)
                          Text('${counts[i]}',
                              style: TextStyle(
                                  color: fg, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (voted)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$total vote${total == 1 ? '' : 's'}',
                style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
          ),
      ],
    );
  }

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
              mapboxTileLayer(),
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
      provider = memoryImageFromB64(m.base64!);
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
    final liveShareId = '${message.raw['live_share_id'] ?? ''}';
    final isLive = message.type == 'live_location' &&
        !message.deleted &&
        liveShareId.isNotEmpty;
    final gameId = '${message.raw['game_id'] ?? ''}';
    final gameType = '${message.raw['game_type'] ?? 'tictactoe'}';
    final isGame =
        message.type == 'game' && !message.deleted && gameId.isNotEmpty;
    final isPoll = message.type == 'poll' && !message.deleted;
    final isTip = (message.type == 'tip' || message.type == 'money') &&
        !message.deleted;
    final tipAmount = (message.raw['amount'] as num?);
    final typeLabel = switch (message.type) {
      'post' => '📄 Shared a post',
      'place' => '📍 Location',
      'live_location' => '📍 Live location',
      'game' => '🎮 ${_gameMeta(gameType).$1}',
      'money' || 'tip' => '💸 Payment',
      'gif' => 'GIF',
      'voice' => '🎤 Voice message',
      'contact' => '👤 Contact',
      'file' => '📎 ${message.raw['file_name'] ?? 'File'}',
      'form' => '📋 Form',
      'call' => _callLabel(message),
      _ => '[${message.type}]',
    };
    // Call events carry no text (the server leaves it empty), so show the
    // call label rather than an empty bubble.
    final isCall = message.type == 'call';
    final bodyText = message.deleted
        ? 'Message deleted'
        : isCall
            ? typeLabel
            : ((message.text?.isNotEmpty ?? false)
                ? message.text!
                : (hasMedia || hasPlace || isLive || isGame || isPoll || isTip
                    ? ''
                    : typeLabel));
    // A short, all-emoji message renders large with no bubble (like WhatsApp).
    final t = (message.text ?? '').trim();
    final emojiOnly = !message.deleted &&
        !hasMedia &&
        !hasPlace &&
        !isLive &&
        !isGame &&
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
                  if (isLive)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: bodyText.isEmpty ? 4 : 6),
                      child: _LiveLocationCard(
                        shareId: liveShareId,
                        mine: mine,
                        fallbackLat: placeLat,
                        fallbackLng: placeLng,
                        initialActive: message.raw['live_active'] != false,
                        onStop: onStopLive,
                      ),
                    ),
                  if (isGame)
                    Padding(
                      padding:
                          EdgeInsets.only(bottom: bodyText.isEmpty ? 4 : 6),
                      child: _GameChip(
                          gameId: gameId,
                          gameType: gameType,
                          mine: mine,
                          otherUserId: otherUserId,
                          difficulty:
                              '${message.raw['difficulty'] ?? 'medium'}',
                          bet: (message.raw['bet'] as num?)?.toInt() ?? 0),
                    ),
                  if (isTip)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.volunteer_activism, color: fg, size: 20),
                      const SizedBox(width: 8),
                      Text(
                          tipAmount != null
                              ? 'Tip · ${tipAmount.toStringAsFixed(2)}'
                              : 'Sent a tip',
                          style: TextStyle(
                              color: fg, fontWeight: FontWeight.bold)),
                    ]),
                  if (isPoll) _pollCard(fg),
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
                                  _hasCustomEmoji(bodyText)
                                      ? _emojiText(bodyText, TextStyle(color: fg))
                                      : _hasMarkdown(bodyText)
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

/// Sentinel row for the "messages are encrypted" notice at the top of history.
const Object _encBanner = _EncBanner();

class _EncBanner {
  const _EncBanner();
}

/// A subtle, centered "messages are encrypted" notice (WhatsApp-style).
class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 14, color: Color(0xFF16A34A)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Messages in this chat are encrypted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

/// A tabbed gallery of everything shared in a conversation: Media, Files, Links.
class _SharedGalleryScreen extends StatelessWidget {
  const _SharedGalleryScreen({required this.messages});

  final List<Message> messages;

  static final _urlRe = RegExp(r'https?://[^\s]+');

  ImageProvider? _providerFor(Message m) {
    if (m.media.isEmpty) return null;
    final media = m.media.first;
    if (media.url != null && media.url!.isNotEmpty) return NetworkImage(media.url!);
    if (media.base64 != null && media.base64!.isNotEmpty) {
      return memoryImageFromB64(media.base64!);
    }
    return null;
  }

  String _fmtSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photos = [
      for (final m in messages)
        if (_providerFor(m) != null) (m, _providerFor(m)!)
    ];
    final files = messages.where((m) => m.type == 'file').toList();
    // (url, message) pairs extracted from text.
    final links = <String>[];
    for (final m in messages) {
      final t = m.text;
      if (t == null) continue;
      for (final match in _urlRe.allMatches(t)) {
        links.add(match.group(0)!);
      }
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: const OkayAppBar(
          title: Text('Shared'),
          bottom: TabBar(tabs: [
            Tab(text: 'Media'),
            Tab(text: 'Files'),
            Tab(text: 'Links'),
          ]),
        ),
        body: TabBarView(
          children: [
            // Media
            photos.isEmpty
                ? const CenteredMessage(
                    message: 'No photos shared yet.',
                    icon: Icons.photo_library_outlined)
                : GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2),
                    itemCount: photos.length,
                    itemBuilder: (c, i) {
                      final provider = photos[i].$2;
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
            // Files
            files.isEmpty
                ? const CenteredMessage(
                    message: 'No files shared yet.',
                    icon: Icons.insert_drive_file_outlined)
                : ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final m = files[i];
                      final name = '${m.raw['file_name'] ?? 'File'}';
                      final size = m.raw['file_size'];
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: size is num ? Text(_fmtSize(size.toInt())) : null,
                      );
                    },
                  ),
            // Links
            links.isEmpty
                ? const CenteredMessage(
                    message: 'No links shared yet.', icon: Icons.link_off)
                : ListView.separated(
                    itemCount: links.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) => ListTile(
                      leading: Icon(Icons.link, color: scheme.primary),
                      title: Text(links[i],
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.copy, size: 18),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: links[i]));
                        showInfo(c, 'Link copied');
                      },
                    ),
                  ),
          ],
        ),
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

  /// Opens (or creates) the private notes-to-self conversation.
  Future<void> _notesToSelf() async {
    final me = currentUserId;
    if (me == null) return;
    try {
      final conv = await api.messaging.startDirect(me);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) =>
            ChatScreen(conversation: conv, title: 'Notes to self'),
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _notesTile() => ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.bookmark_outline,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: const Text('Notes to self'),
        subtitle: const Text('A private place to save thoughts & places'),
        onTap: _notesToSelf,
      );

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
          ? ListView(
              children: [
                _notesTile(),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                  child: Column(
                    children: [
                      Icon(Icons.search,
                          size: 48,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('Search for someone to message.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
              ],
            )
          : AsyncList<PublicUser>(
              future: _results!,
              emptyMessage: 'No people found.',
              emptyIcon: Icons.person_search_outlined,
              builder: (context, items) => ListView.builder(
                itemCount: items.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _notesTile();
                  final u = items[i - 1];
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
/// (label, icon, accent) for an in-chat game type.
(String, IconData, Color) _gameMeta(String type) {
  switch (type) {
    case 'blackjack':
      return ('Blackjack', Icons.style_outlined, const Color(0xFF16A34A));
    case 'chess':
      return ('Chess', Icons.shield_outlined, const Color(0xFF6B7280));
    case 'checkers':
      return ('Checkers', Icons.circle_outlined, const Color(0xFFDC2626));
    case 'poker':
      return ('Poker', Icons.casino_outlined, const Color(0xFF7C3AED));
    case 'pong':
      return ('Pong', Icons.sports_tennis, const Color(0xFF0EA5E9));
    case 'snake':
      return ('Snake', Icons.linear_scale, const Color(0xFF22C55E));
    case 'connect4':
      return ('Connect 4', Icons.grid_view, const Color(0xFFF59E0B));
    case 'dotsboxes':
      return ('Dots & Boxes', Icons.border_all, const Color(0xFF14B8A6));
    default:
      return ('Tic-tac-toe', Icons.grid_3x3, const Color(0xFF2563EB));
  }
}

/// Opens the game in a popup dialog (the board lives here, not in the bubble).
/// Game types that render as a Three.js (WebGL) WebView when supported.
const _threeGames = {
  'pong', 'snake', 'tictactoe', 'chess', 'checkers', 'blackjack', 'poker',
  'connect4', 'dotsboxes',
};

/// Opens a game on its own full-screen page (back returns to the chat).
void _openGamePage(BuildContext context, String gameId, String gameType,
    bool mine, String? otherUserId,
    [String difficulty = 'medium']) {
  final (label, icon, color) = _gameMeta(gameType);
  final isArcade = gameType == 'pong' || gameType == 'snake';
  final asThree = threeGamesSupported && _threeGames.contains(gameType);
  Navigator.of(context).push(MaterialPageRoute(builder: (ctx) {
    final Widget board = asThree
        ? (isArcade
            ? _ThreeArcade(
                gameId: gameId,
                gameType: gameType,
                otherUserId: otherUserId,
                difficulty: difficulty)
            : _ThreeBridged(gameId: gameId, gameType: gameType, mine: mine))
        : switch (gameType) {
            'blackjack' => _BlackjackBoard(gameId: gameId, mine: mine),
            'chess' => _ChessBoard(gameId: gameId),
            'checkers' => _CheckersBoard(gameId: gameId),
            'poker' => _PokerBoard(gameId: gameId, mine: mine),
            'pong' => _PongBoard(gameId: gameId, otherUserId: otherUserId),
            'snake' => _SnakeBoard(gameId: gameId, otherUserId: otherUserId),
            'tictactoe' => _TicTacToeBoard(gameId: gameId),
            // Games without a native board (e.g. Connect 4, Dots & Boxes) are
            // playable in the web app. Don't fall back to a mismatched board.
            _ => const _WebOnlyGameBoard(),
          };
    return Scaffold(
      appBar: OkayAppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: asThree
                ? board
                : Center(child: SingleChildScrollView(child: board)),
          ),
          // Arcade games show their own high-score line; others show W/L/T.
          if (!isArcade)
            const Padding(
              padding: EdgeInsets.all(10),
              child: _GameStatsFooter(),
            ),
        ]),
      ),
    );
  }));
}

/// Shows the current user's overall win/loss/tie record under a game board,
/// refreshed periodically so it updates once a game finishes.
class _GameStatsFooter extends StatefulWidget {
  const _GameStatsFooter();
  @override
  State<_GameStatsFooter> createState() => _GameStatsFooterState();
}

class _GameStatsFooterState extends State<_GameStatsFooter> {
  GameStats? _s;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final me = currentUserId;
    if (me == null) return;
    try {
      final s = await api.messaging.gameStats(me);
      if (mounted) setState(() => _s = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Text(
      'Your record · ${s.wins}W · ${s.losses}L · ${s.ties}T',
      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
    );
  }
}

/// Compact game card shown in the chat bubble; tap to open the popup.
class _GameChip extends StatelessWidget {
  const _GameChip(
      {required this.gameId,
      required this.gameType,
      required this.mine,
      this.otherUserId,
      this.difficulty = 'medium',
      this.bet = 0});

  final String gameId;
  final String gameType;
  final bool mine;
  final String? otherUserId;
  final String difficulty;
  final int bet;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _gameMeta(gameType);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openGamePage(
          context, gameId, gameType, mine, otherUserId, difficulty),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(bet > 0 ? 'Tap to play · $bet pts' : 'Tap to play',
                    style: TextStyle(
                        fontSize: 12,
                        color: bet > 0 ? color : scheme.onSurfaceVariant,
                        fontWeight:
                            bet > 0 ? FontWeight.w600 : FontWeight.normal)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.outline),
        ]),
      ),
    );
  }
}

/// Shown for games that only have a web (Canvas) renderer when opened on a
/// non-web build, instead of falling back to a mismatched native board.
class _WebOnlyGameBoard extends StatelessWidget {
  const _WebOnlyGameBoard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 56, color: scheme.outline),
            const SizedBox(height: 14),
            const Text('Play this game in the web app',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('It needs a browser to render.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// A small playing-card face (or back when [hidden]).
Widget _playingCard(Map<String, dynamic> c, {bool selected = false}) {
  final r = '${c['r'] ?? '?'}';
  final s = '${c['s'] ?? ''}';
  final hidden = r == '?';
  final red = s == '♥' || s == '♦';
  final ink = red ? const Color(0xFFDC2626) : Colors.black;
  return Container(
    width: 38,
    height: 54,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: hidden ? const Color(0xFF334155) : Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
          color: selected ? const Color(0xFF22C55E) : Colors.black26,
          width: selected ? 2.5 : 1),
    ),
    alignment: Alignment.center,
    child: hidden
        ? const Icon(Icons.help_outline, color: Colors.white70, size: 18)
        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(r,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: ink)),
            Text(s, style: TextStyle(fontSize: 14, color: ink)),
          ]),
  );
}

// ===== Tic-tac-toe board (popup), with a non-instant CPU =====
class _TicTacToeBoard extends StatefulWidget {
  const _TicTacToeBoard({required this.gameId});
  final String gameId;
  @override
  State<_TicTacToeBoard> createState() => _TicTacToeBoardState();
}

class _TicTacToeBoardState extends State<_TicTacToeBoard> {
  GameView? _g;
  Timer? _poll;
  bool _busy = false;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    try {
      final g = await api.messaging.game(widget.gameId);
      if (!mounted) return;
      setState(() => _g = g);
      if (g.isOver) _poll?.cancel();
    } catch (_) {}
  }

  Future<void> _tap(int cell) async {
    final g = _g;
    if (g == null || g.isOver || _busy) return;
    if (g.turn != currentUserId || g.board[cell].isNotEmpty) return;
    setState(() => _busy = true);
    try {
      var v = await api.messaging.gameMove(widget.gameId, cell);
      if (mounted) setState(() => _g = v);
      // The computer pauses before replying so it doesn't move instantly.
      if (!v.isOver && v.turn == 'cpu') {
        setState(() => _thinking = true);
        await Future.delayed(const Duration(milliseconds: 800));
        v = await api.messaging.cpuMove(widget.gameId);
        if (mounted) setState(() => _g = v);
      }
      if (v.isOver) _poll?.cancel();
    } catch (e) {
      if (mounted) showError(context, e);
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _thinking = false;
        });
      }
    }
  }

  String _status(GameView g) {
    if (_thinking) return 'Thinking…';
    final myMark =
        g.xPlayer == currentUserId ? 'X' : (g.oPlayer == currentUserId ? 'O' : '');
    if (g.status == 'draw') return "It's a draw";
    if (g.status == 'won') {
      return g.winner == currentUserId ? 'You won! 🎉' : 'You lost';
    }
    if (myMark.isEmpty) return g.turn == g.xPlayer ? "X's turn" : "O's turn";
    return g.turn == currentUserId ? 'Your turn ($myMark)' : 'Their turn';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = _g;
    if (g == null) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 300,
        height: 300,
        child: GridView.count(
          crossAxisCount: 3,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (int i = 0; i < 9; i++)
              GestureDetector(
                onTap: () => _tap(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(g.board[i],
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: g.board[i] == 'X'
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFEF4444))),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(_status(g),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ===== Blackjack board (popup) =====
class _BlackjackBoard extends StatefulWidget {
  const _BlackjackBoard({required this.gameId, required this.mine});
  final String gameId;
  final bool mine;
  @override
  State<_BlackjackBoard> createState() => _BlackjackBoardState();
}

class _BlackjackBoardState extends State<_BlackjackBoard> {
  BlackjackView? _v;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await api.messaging.blackjack(widget.gameId);
      if (mounted) setState(() => _v = v);
    } catch (_) {}
  }

  Future<void> _act(Future<BlackjackView> Function() call) async {
    setState(() => _busy = true);
    try {
      final v = await call();
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _result(String s) => switch (s) {
        'blackjack' => 'Blackjack! You win 🎉',
        'win' => 'You win 🎉',
        'lose' => 'Dealer wins',
        'push' => 'Push — a tie',
        _ => '',
      };

  Widget _row(List<Map<String, dynamic>> cards) => Wrap(
      children: [for (final c in cards) _playingCard(c)]);

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return const SizedBox(
          height: 160, child: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: Text('Dealer  ${v.isOver ? v.dealerTotal : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant))),
      const SizedBox(height: 4),
      _row(v.dealer),
      const SizedBox(height: 14),
      Align(
          alignment: Alignment.centerLeft,
          child: Text('You  ${v.playerTotal}',
              style: TextStyle(color: scheme.onSurfaceVariant))),
      const SizedBox(height: 4),
      _row(v.player),
      const SizedBox(height: 14),
      if (v.isOver)
        Text(_result(v.status),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))
      else if (widget.mine)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton(
              onPressed: _busy ? null : () => _act(() => api.messaging.blackjackHit(widget.gameId)),
              child: const Text('Hit')),
          const SizedBox(width: 12),
          OutlinedButton(
              onPressed: _busy ? null : () => _act(() => api.messaging.blackjackStand(widget.gameId)),
              child: const Text('Stand')),
        ])
      else
        Text('Watching', style: TextStyle(color: scheme.onSurfaceVariant)),
    ]);
  }
}

// ===== Chess board (popup) =====
// Black-series glyphs for black pieces, white-series for white: on iOS these
// render as emoji that ignore the text colour, so the glyph itself must carry
// the colour or both sides look identical.
const _chessGlyph = {
  'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟',
};
const _chessGlyphWhite = {
  'k': '♔', 'q': '♕', 'r': '♖', 'b': '♗', 'n': '♘', 'p': '♙',
};

String _sqName(int i) =>
    '${String.fromCharCode(97 + i % 8)}${8 - i ~/ 8}';

class _ChessBoard extends StatefulWidget {
  const _ChessBoard({required this.gameId});
  final String gameId;
  @override
  State<_ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<_ChessBoard> {
  ChessView? _v;
  Timer? _poll;
  int? _sel;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    try {
      final v = await api.messaging.chess(widget.gameId);
      if (mounted) setState(() => _v = v);
      if (v.isOver) _poll?.cancel();
    } catch (_) {}
  }

  Future<void> _tap(int sq) async {
    final v = _v;
    if (v == null || v.isOver || _busy || v.turn != currentUserId) return;
    final amWhite = v.whitePlayer == currentUserId;
    final p = v.board[sq];
    final mineHere = p != '.' &&
        (amWhite ? p == p.toUpperCase() : p == p.toLowerCase());
    if (_sel == null) {
      if (mineHere) setState(() => _sel = sq);
      return;
    }
    if (sq == _sel || mineHere) {
      setState(() => _sel = mineHere ? sq : null);
      return;
    }
    setState(() => _busy = true);
    try {
      var nv = await api.messaging
          .chessMove(widget.gameId, _sqName(_sel!), _sqName(sq));
      if (mounted) {
        setState(() {
          _v = nv;
          _sel = null;
        });
      }
      // Playing the computer: let it reply after a brief pause.
      if (!nv.isOver && nv.turn == 'cpu') {
        await Future.delayed(const Duration(milliseconds: 300));
        nv = await api.messaging.chessCpuMove(widget.gameId);
        if (mounted) setState(() => _v = nv);
      }
      if (nv.isOver) _poll?.cancel();
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _sel = null);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(ChessView v) {
    if (v.status == 'checkmate') {
      return v.winner == currentUserId ? 'Checkmate — you win 🎉' : 'Checkmate — you lost';
    }
    if (v.status == 'stalemate') return 'Stalemate — draw';
    if (v.status == 'draw') return 'Draw';
    final mine = v.turn == currentUserId;
    return '${mine ? 'Your move' : 'Their move'}${v.inCheck ? ' · check!' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return const SizedBox(
          height: 300, child: Center(child: CircularProgressIndicator()));
    }
    final amWhite = v.whitePlayer == currentUserId;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 320,
        height: 320,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8),
          itemCount: 64,
          itemBuilder: (_, k) {
            final sq = amWhite ? k : 63 - k;
            final p = v.board[sq];
            final light = ((sq % 8) + (sq ~/ 8)) % 2 == 0;
            final sel = _sel == sq;
            return GestureDetector(
              onTap: () => _tap(sq),
              child: Container(
                color: sel
                    ? const Color(0xFF86EFAC)
                    : (light
                        ? const Color(0xFFEDD9B5)
                        : const Color(0xFFB48761)),
                alignment: Alignment.center,
                child: p == '.'
                    ? null
                    : Text(
                        (p == p.toUpperCase()
                                ? _chessGlyphWhite
                                : _chessGlyph)[p.toLowerCase()] ??
                            '',
                        style: TextStyle(
                            fontSize: 28,
                            color: p == p.toUpperCase()
                                ? Colors.white
                                : Colors.black,
                            shadows: const [
                              Shadow(blurRadius: 1, color: Colors.black54),
                            ])),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Text(_status(v),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ===== Checkers board (popup) =====
class _CheckersBoard extends StatefulWidget {
  const _CheckersBoard({required this.gameId});
  final String gameId;
  @override
  State<_CheckersBoard> createState() => _CheckersBoardState();
}

class _CheckersBoardState extends State<_CheckersBoard> {
  CheckersView? _v;
  Timer? _poll;
  int? _sel;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy || _sel != null) return;
    try {
      final v = await api.messaging.checkers(widget.gameId);
      if (mounted) setState(() => _v = v);
      if (v.isOver) _poll?.cancel();
    } catch (_) {}
  }

  Future<void> _tap(int sq) async {
    final v = _v;
    if (v == null || v.isOver || _busy || v.turn != currentUserId) return;
    final amWhite = v.whitePlayer == currentUserId;
    final p = v.board[sq];
    final mineHere = amWhite ? (p == 'w' || p == 'W') : (p == 'b' || p == 'B');
    if (_sel == null) {
      if (mineHere) setState(() => _sel = sq);
      return;
    }
    if (sq == _sel || mineHere) {
      setState(() => _sel = mineHere ? sq : null);
      return;
    }
    setState(() => _busy = true);
    try {
      var nv = await api.messaging.checkersMove(widget.gameId, _sel!, sq);
      if (mounted) {
        setState(() {
          _v = nv;
          // A multi-jump keeps the turn: stay selected on the chaining square.
          _sel =
              (nv.turn == currentUserId && nv.chain != null) ? nv.chain : null;
        });
      }
      // Playing the computer: let it reply after a brief pause.
      if (!nv.isOver && nv.turn == 'cpu') {
        await Future.delayed(const Duration(milliseconds: 300));
        nv = await api.messaging.checkersCpuMove(widget.gameId);
        if (mounted) setState(() => _v = nv);
      }
      if (nv.isOver) _poll?.cancel();
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _sel = null);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(CheckersView v) {
    if (v.isOver) {
      return v.winner == currentUserId ? 'You win 🎉' : 'You lost';
    }
    return v.turn == currentUserId ? 'Your move' : 'Their move';
  }

  Widget _piece(String p) {
    final white = p == 'w' || p == 'W';
    final king = p == 'W' || p == 'B';
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: white ? const Color(0xFFF1F5F9) : const Color(0xFF1F2937),
        border: Border.all(color: Colors.black54, width: 1.5),
      ),
      alignment: Alignment.center,
      child: king
          ? Icon(Icons.star,
              size: 14, color: white ? Colors.amber[800] : Colors.amber)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return const SizedBox(
          height: 300, child: Center(child: CircularProgressIndicator()));
    }
    final amWhite = v.whitePlayer == currentUserId;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 320,
        height: 320,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8),
          itemCount: 64,
          itemBuilder: (_, k) {
            final sq = amWhite ? k : 63 - k;
            final p = v.board[sq];
            final dark = ((sq % 8) + (sq ~/ 8)) % 2 == 1;
            final sel = _sel == sq;
            return GestureDetector(
              onTap: () => _tap(sq),
              child: Container(
                color: sel
                    ? const Color(0xFF86EFAC)
                    : (dark
                        ? const Color(0xFF8D6748)
                        : const Color(0xFFEAD9BD)),
                alignment: Alignment.center,
                child: p == '.' ? null : _piece(p),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Text(_status(v),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ===== Poker board (popup): five-card draw vs the dealer =====
class _PokerBoard extends StatefulWidget {
  const _PokerBoard({required this.gameId, required this.mine});
  final String gameId;
  final bool mine;
  @override
  State<_PokerBoard> createState() => _PokerBoardState();
}

class _PokerBoardState extends State<_PokerBoard> {
  PokerView? _v;
  final Set<int> _holds = {};
  bool _busy = false;
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await api.messaging.poker(widget.gameId);
      if (mounted) setState(() => _v = v);
    } catch (_) {}
  }

  Future<void> _draw() async {
    setState(() => _busy = true);
    try {
      var v = await api.messaging.pokerDraw(widget.gameId, _holds.toList());
      if (mounted) setState(() => _v = v);
      // The dealer pauses before revealing — not instant.
      setState(() => _revealing = true);
      await Future.delayed(const Duration(milliseconds: 900));
      v = await api.messaging.pokerReveal(widget.gameId);
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _revealing = false;
        });
      }
    }
  }

  String _result(String s) => switch (s) {
        'win' => 'You win 🎉',
        'lose' => 'Dealer wins',
        'push' => 'Split pot — tie',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    final canDraw = widget.mine && v.status == 'active' && !_busy;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Align(
          alignment: Alignment.centerLeft,
          child: Text('Dealer${v.opponentHand != null ? ' · ${v.opponentHand}' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant))),
      const SizedBox(height: 4),
      Wrap(children: [for (final c in v.opponent) _playingCard(c)]),
      const SizedBox(height: 14),
      Align(
          alignment: Alignment.centerLeft,
          child: Text('You · ${v.yourHand}',
              style: TextStyle(color: scheme.onSurfaceVariant))),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < v.you.length; i++)
            GestureDetector(
              onTap: canDraw
                  ? () => setState(() =>
                      _holds.contains(i) ? _holds.remove(i) : _holds.add(i))
                  : null,
              child: _playingCard(v.you[i], selected: _holds.contains(i)),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (v.isOver)
        Text(_result(v.status),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))
      else if (_revealing)
        const Text('Dealer drawing…')
      else if (canDraw) ...[
        Text('Tap cards to keep, then draw',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        FilledButton(onPressed: _draw, child: const Text('Draw')),
      ] else
        Text('Watching', style: TextStyle(color: scheme.onSurfaceVariant)),
    ]);
  }
}

/// Shows the player's best arcade score and (in a DM) the partner's, so two
/// people can see who's ahead.
class _ArcadeScores extends StatelessWidget {
  const _ArcadeScores({required this.mine, this.theirs});
  final int mine;
  final int? theirs;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cmp = theirs == null
        ? ''
        : (mine > theirs! ? "  · You're ahead 🏆" : (mine < theirs! ? '  · Behind' : '  · Tied'));
    return Text(
      'Your best: $mine${theirs != null ? '  ·  Their best: $theirs' : ''}$cmp',
      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
    );
  }
}

/// Hosts a self-contained arcade game and, when it ends, reports the score and
/// shows the high-score comparison.
class _ThreeArcade extends StatefulWidget {
  const _ThreeArcade(
      {required this.gameId,
      required this.gameType,
      this.otherUserId,
      this.difficulty = 'medium'});
  final String gameId;
  final String gameType;
  final String? otherUserId;
  final String difficulty;
  @override
  State<_ThreeArcade> createState() => _ThreeArcadeState();
}

class _ThreeArcadeState extends State<_ThreeArcade> {
  int? _myBest;
  int? _theirBest;

  Future<void> _onScore(int score) async {
    try {
      final mine = await api.messaging.reportScore(widget.gameId, score);
      int? other;
      if (widget.otherUserId != null) {
        other = (await api.messaging.gameScores(widget.otherUserId!))
            .best(widget.gameType);
      }
      if (mounted) {
        setState(() {
          _myBest = mine.best(widget.gameType);
          _theirBest = other;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ThreeGameView(
            gameType: widget.gameType,
            initialState: {'difficulty': widget.difficulty},
            onScore: _onScore),
      ),
      if (_myBest != null)
        Padding(
          padding: const EdgeInsets.all(10),
          child: _ArcadeScores(mine: _myBest!, theirs: _theirBest),
        ),
    ]);
  }
}

/// Hosts a backend-driven Three.js game: loads the initial state, renders it in
/// the WebGL view, and resolves each move the WebView sends against the API,
/// pushing the new state back. Tic-tac-toe today; chess/checkers/etc. plug in
/// here by adding an [_actionFor] branch.
class _ThreeBridged extends StatefulWidget {
  const _ThreeBridged(
      {required this.gameId, required this.gameType, this.mine = false});
  final String gameId;
  final String gameType;
  final bool mine;
  @override
  State<_ThreeBridged> createState() => _ThreeBridgedState();
}

class _ThreeBridgedState extends State<_ThreeBridged> {
  Map<String, dynamic>? _initial;
  bool _failed = false;
  bool _busy = false;
  String? _lastEncoded;
  Timer? _poll;
  final _updates = StreamController<Map<String, dynamic>>.broadcast();

  static const _twoPlayer = {
    'tictactoe', 'chess', 'checkers', 'connect4', 'dotsboxes'
  };

  @override
  void initState() {
    super.initState();
    _load();
    // Two-player games poll so the opponent's moves show up.
    if (_twoPlayer.contains(widget.gameType)) {
      _poll = Timer.periodic(
          const Duration(seconds: 3), (_) => _pollState());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _updates.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _fetchState();
      _lastEncoded = jsonEncode(s);
      if (mounted) setState(() => _initial = s);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Re-fetch and push the state to the WebView when it changed (opponent move).
  Future<void> _pollState() async {
    if (_busy || !mounted) return;
    try {
      final s = await _fetchState();
      final enc = jsonEncode(s);
      if (enc != _lastEncoded) {
        _lastEncoded = enc;
        _updates.add(s);
      }
    } catch (_) {}
  }

  /// Current state of the game as a plain map the WebView understands.
  Future<Map<String, dynamic>> _fetchState() async {
    final api2 = api.messaging;
    switch (widget.gameType) {
      case 'tictactoe':
        return _tttState(await api2.game(widget.gameId));
      case 'chess':
        return _chessState(await api2.chess(widget.gameId));
      case 'checkers':
        return _checkersState(await api2.checkers(widget.gameId));
      case 'connect4':
        return _c4State(await api2.connect4(widget.gameId));
      case 'dotsboxes':
        return _dbxState(await api2.dotsboxes(widget.gameId));
      case 'blackjack':
        return _bjState(await api2.blackjack(widget.gameId));
      case 'poker':
        return _pokerState(await api2.poker(widget.gameId));
      default:
        return const {};
    }
  }

  Map<String, dynamic> _tttState(GameView g) => {
        'board': g.board,
        'turn': g.turn,
        'status': g.status,
        'winner': g.winner,
        'x': g.xPlayer,
        'o': g.oPlayer,
        'you': currentUserId,
      };

  Map<String, dynamic> _chessState(ChessView v) => {
        'board': v.board,
        'turn': v.turn,
        'status': v.status,
        'winner': v.winner,
        'white': v.whitePlayer,
        'black': v.blackPlayer,
        'inCheck': v.inCheck,
        'you': currentUserId,
      };

  Map<String, dynamic> _checkersState(CheckersView v) => {
        'board': v.board,
        'turn': v.turn,
        'status': v.status,
        'winner': v.winner,
        'white': v.whitePlayer,
        'black': v.blackPlayer,
        'chain': v.chain,
        'you': currentUserId,
      };

  Map<String, dynamic> _c4State(ConnectFourView v) => {
        'board': v.board,
        'turn': v.turn,
        'status': v.status,
        'winner': v.winner,
        'red': v.redPlayer,
        'yellow': v.yellowPlayer,
        'you': currentUserId,
      };

  Map<String, dynamic> _dbxState(DotsBoxesView v) => {
        'h': v.h,
        'v': v.v,
        'owner': v.owner,
        'dots': v.dots,
        'turn': v.turn,
        'status': v.status,
        'winner': v.winner,
        'red': v.redPlayer,
        'yellow': v.yellowPlayer,
        'redScore': v.redScore,
        'yellowScore': v.yellowScore,
        'you': currentUserId,
      };

  Map<String, dynamic> _bjState(BlackjackView v) => {
        'player': v.player,
        'dealer': v.dealer,
        'playerTotal': v.playerTotal,
        'dealerTotal': v.dealerTotal,
        'status': v.status,
        'mine': widget.mine,
      };

  Map<String, dynamic> _pokerState(PokerView v) => {
        'you': v.you,
        'opponent': v.opponent,
        'yourHand': v.yourHand,
        'opponentHand': v.opponentHand,
        'status': v.status,
        'mine': widget.mine,
      };

  /// Applies a move from the WebView and returns the resulting state.
  Future<Map<String, dynamic>?> _onAction(Map<String, dynamic> action) async {
    _busy = true;
    try {
      final next = await _resolveAction(action);
      if (next != null) _lastEncoded = jsonEncode(next);
      return next;
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>?> _resolveAction(
      Map<String, dynamic> action) async {
    final api2 = api.messaging;
    try {
      // Play again: reset the game, then hand back the fresh state.
      if (action['move'] == 'rematch') {
        await api2.rematch(widget.gameId);
        return _fetchState();
      }
      switch (widget.gameType) {
        case 'tictactoe':
          final cell = action['cell'];
          if (cell is! int) return null;
          var g = await api2.gameMove(widget.gameId, cell);
          if (!g.isOver && g.turn == 'cpu') {
            // Show the player's move right away (with "Thinking…") before the
            // CPU pauses and replies — so it doesn't feel laggy.
            _updates.add(_tttState(g));
            await Future.delayed(const Duration(milliseconds: 600));
            g = await api2.cpuMove(widget.gameId);
          }
          return _tttState(g);
        case 'chess':
          var v = await api2.chessMove(
              widget.gameId, '${action['from']}', '${action['to']}');
          if (!v.isOver && v.turn == 'cpu') {
            _updates.add(_chessState(v)); // show my move immediately
            await Future.delayed(const Duration(milliseconds: 300));
            v = await api2.chessCpuMove(widget.gameId);
          }
          return _chessState(v);
        case 'checkers':
          final from = action['from'], to = action['to'];
          if (from is! int || to is! int) return null;
          var c = await api2.checkersMove(widget.gameId, from, to);
          if (!c.isOver && c.turn == 'cpu') {
            _updates.add(_checkersState(c));
            await Future.delayed(const Duration(milliseconds: 300));
            c = await api2.checkersCpuMove(widget.gameId);
          }
          return _checkersState(c);
        case 'connect4':
          final col = action['col'];
          if (col is! int) return null;
          var v = await api2.connect4Move(widget.gameId, col);
          if (!v.isOver && v.turn == 'cpu') {
            _updates.add(_c4State(v)); // show my drop immediately
            await Future.delayed(const Duration(milliseconds: 300));
            v = await api2.connect4CpuMove(widget.gameId);
          }
          return _c4State(v);
        case 'dotsboxes':
          final kind = action['kind'], idx = action['idx'];
          if (kind is! String || idx is! int) return null;
          var d = await api2.dotsboxesMove(widget.gameId, kind, idx);
          if (!d.isOver && d.turn == 'cpu') {
            _updates.add(_dbxState(d)); // show my edge immediately
            await Future.delayed(const Duration(milliseconds: 300));
            d = await api2.dotsboxesCpuMove(widget.gameId);
          }
          return _dbxState(d);
        case 'blackjack':
          final m = action['move'];
          if (m == 'hit') return _bjState(await api2.blackjackHit(widget.gameId));
          if (m == 'stand') {
            return _bjState(await api2.blackjackStand(widget.gameId));
          }
          return _bjState(await api2.blackjack(widget.gameId));
        case 'poker':
          final m = action['move'];
          if (m == 'draw') {
            final holds = (action['holds'] as List?)
                    ?.whereType<num>()
                    .map((e) => e.toInt())
                    .toList() ??
                const <int>[];
            await api2.pokerDraw(widget.gameId, holds);
            await Future.delayed(const Duration(milliseconds: 800));
            return _pokerState(await api2.pokerReveal(widget.gameId));
          }
          return _pokerState(await api2.poker(widget.gameId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
      // Recover by re-rendering the true state, so an illegal/failed move
      // doesn't leave the board stuck on a "..." placeholder.
      try {
        return await _fetchState();
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Text("Couldn't load this game"));
    }
    final init = _initial;
    if (init == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ThreeGameView(
      gameType: widget.gameType,
      initialState: init,
      onAction: _onAction,
      stateStream: _updates.stream,
    );
  }
}

// ===== Pong (real-time, vs a CPU paddle) =====
class _PongBoard extends StatefulWidget {
  const _PongBoard({required this.gameId, this.otherUserId});
  final String gameId;
  final String? otherUserId;
  @override
  State<_PongBoard> createState() => _PongBoardState();
}

class _PongBoardState extends State<_PongBoard> {
  static const _w = 300.0, _h = 340.0;
  static const _pw = 64.0, _ph = 10.0, _ballR = 7.0, _target = 7;
  Timer? _loop;
  // Positions in pixels.
  double _px = _w / 2; // player paddle centre x (bottom)
  double _cx = _w / 2; // cpu paddle centre x (top)
  double _bx = _w / 2, _by = _h / 2; // ball
  double _vx = 2.4, _vy = -3.2;
  int _pScore = 0, _cScore = 0;
  bool _over = false;
  int _myBest = 0;
  int? _theirBest;

  @override
  void initState() {
    super.initState();
    _loop = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  void _reset(bool toPlayer) {
    _bx = _w / 2;
    _by = _h / 2;
    _vx = (math.Random().nextBool() ? 2.4 : -2.4);
    _vy = toPlayer ? 3.2 : -3.2;
  }

  void _tick() {
    if (_over) return;
    setState(() {
      // CPU tracks the ball with a capped speed (beatable).
      final target = _bx.clamp(_pw / 2, _w - _pw / 2);
      _cx += (target - _cx).clamp(-2.6, 2.6);
      _bx += _vx;
      _by += _vy;
      if (_bx < _ballR || _bx > _w - _ballR) _vx = -_vx;
      // Top paddle (CPU).
      if (_by < _ph + _ballR) {
        if ((_bx - _cx).abs() < _pw / 2) {
          _vy = _vy.abs();
        } else {
          _pScore++;
          if (_pScore >= _target) {
            _finish();
            return;
          }
          _reset(false);
        }
      }
      // Bottom paddle (player).
      if (_by > _h - _ph - _ballR) {
        if ((_bx - _px).abs() < _pw / 2) {
          _vy = -_vy.abs();
        } else {
          _cScore++;
          if (_cScore >= _target) {
            _finish();
            return;
          }
          _reset(true);
        }
      }
    });
  }

  Future<void> _finish() async {
    _loop?.cancel();
    setState(() => _over = true);
    try {
      final mine = await api.messaging.reportScore(widget.gameId, _pScore);
      int? other;
      if (widget.otherUserId != null) {
        other = (await api.messaging.gameScores(widget.otherUserId!)).best('pong');
      }
      if (mounted) {
        setState(() {
          _myBest = mine.best('pong');
          _theirBest = other;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('You $_pScore  —  CPU $_cScore',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 6),
      GestureDetector(
        onPanUpdate: (d) => setState(() => _px =
            (_px + d.delta.dx).clamp(_pw / 2, _w - _pw / 2)),
        onTapDown: (d) =>
            setState(() => _px = d.localPosition.dx.clamp(_pw / 2, _w - _pw / 2)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(
            size: const Size(_w, _h),
            painter: _PongPainter(
                px: _px, cx: _cx, bx: _bx, by: _by, pw: _pw, ph: _ph, r: _ballR),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (_over)
        Column(children: [
          Text(_pScore > _cScore ? 'You win 🎉' : 'CPU wins',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          _ArcadeScores(mine: _myBest, theirs: _theirBest),
        ])
      else
        Text('Drag to move your paddle',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline)),
    ]);
  }
}

class _PongPainter extends CustomPainter {
  _PongPainter(
      {required this.px,
      required this.cx,
      required this.bx,
      required this.by,
      required this.pw,
      required this.ph,
      required this.r});
  final double px, cx, bx, by, pw, ph, r;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Offset.zero & size, bg);
    final line = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, size.height / 2),
        Offset(size.width, size.height / 2), line);
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, ph / 2 + 2), width: pw, height: ph),
            const Radius.circular(4)),
        white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(px, size.height - ph / 2 - 2),
                width: pw,
                height: ph),
            const Radius.circular(4)),
        white);
    canvas.drawCircle(Offset(bx, by), r, white);
  }

  @override
  bool shouldRepaint(_PongPainter old) =>
      old.px != px || old.cx != cx || old.bx != bx || old.by != by;
}

// ===== Snake (real-time, solo) =====
class _SnakeBoard extends StatefulWidget {
  const _SnakeBoard({required this.gameId, this.otherUserId});
  final String gameId;
  final String? otherUserId;
  @override
  State<_SnakeBoard> createState() => _SnakeBoardState();
}

class _SnakeBoardState extends State<_SnakeBoard> {
  static const _n = 15; // grid size
  static const _px = 300.0;
  final _rng = math.Random();
  Timer? _loop;
  List<math.Point<int>> _snake = [];
  math.Point<int> _dir = const math.Point(1, 0);
  math.Point<int> _pendingDir = const math.Point(1, 0);
  late math.Point<int> _food;
  int _score = 0;
  bool _over = false;
  int _myBest = 0;
  int? _theirBest;

  @override
  void initState() {
    super.initState();
    _snake = [const math.Point(7, 7), const math.Point(6, 7), const math.Point(5, 7)];
    _food = _spawnFood();
    _loop = Timer.periodic(const Duration(milliseconds: 170), (_) => _tick());
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  math.Point<int> _spawnFood() {
    while (true) {
      final p = math.Point(_rng.nextInt(_n), _rng.nextInt(_n));
      if (!_snake.contains(p)) return p;
    }
  }

  void _steer(int dx, int dy) {
    // No reversing onto yourself.
    if (dx == -_dir.x && dy == -_dir.y) return;
    _pendingDir = math.Point(dx, dy);
  }

  void _tick() {
    if (_over) return;
    _dir = _pendingDir;
    final head = _snake.first;
    final nh = math.Point(head.x + _dir.x, head.y + _dir.y);
    if (nh.x < 0 || nh.y < 0 || nh.x >= _n || nh.y >= _n || _snake.contains(nh)) {
      _finish();
      return;
    }
    setState(() {
      _snake.insert(0, nh);
      if (nh == _food) {
        _score++;
        _food = _spawnFood();
      } else {
        _snake.removeLast();
      }
    });
  }

  Future<void> _finish() async {
    _loop?.cancel();
    setState(() => _over = true);
    try {
      final mine = await api.messaging.reportScore(widget.gameId, _score);
      int? other;
      if (widget.otherUserId != null) {
        other = (await api.messaging.gameScores(widget.otherUserId!)).best('snake');
      }
      if (mounted) {
        setState(() {
          _myBest = mine.best('snake');
          _theirBest = other;
        });
      }
    } catch (_) {}
  }

  void _onPan(DragUpdateDetails d) {
    if (d.delta.dx.abs() > d.delta.dy.abs()) {
      _steer(d.delta.dx > 0 ? 1 : -1, 0);
    } else {
      _steer(0, d.delta.dy > 0 ? 1 : -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Score: $_score',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 6),
      GestureDetector(
        onPanUpdate: _over ? null : _onPan,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CustomPaint(
            size: const Size(_px, _px),
            painter: _SnakePainter(snake: _snake, food: _food, n: _n),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (_over)
        Column(children: [
          const Text('Game over',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          _ArcadeScores(mine: _myBest, theirs: _theirBest),
        ])
      else
        Text('Swipe to steer',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.outline)),
    ]);
  }
}

class _SnakePainter extends CustomPainter {
  _SnakePainter({required this.snake, required this.food, required this.n});
  final List<math.Point<int>> snake;
  final math.Point<int> food;
  final int n;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / n;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0B1220));
    final foodP = Paint()..color = const Color(0xFFEF4444);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(food.x * cell + 1, food.y * cell + 1, cell - 2,
                cell - 2),
            const Radius.circular(3)),
        foodP);
    for (var i = 0; i < snake.length; i++) {
      final p = Paint()
        ..color = i == 0 ? const Color(0xFF4ADE80) : const Color(0xFF22C55E);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(snake[i].x * cell + 1, snake[i].y * cell + 1,
                  cell - 2, cell - 2),
              const Radius.circular(3)),
          p);
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => true;
}

/// In-bubble live-location view: a small map that polls the share and tracks
/// the sharer's moving dot, with a status line and (for the sharer) a Stop
/// button. Stops polling once the share ends or expires.
class _LiveLocationCard extends StatefulWidget {
  const _LiveLocationCard({
    required this.shareId,
    required this.mine,
    this.fallbackLat,
    this.fallbackLng,
    this.initialActive = true,
    this.onStop,
  });

  final String shareId;
  final bool mine;
  final double? fallbackLat;
  final double? fallbackLng;
  final bool initialActive;
  final VoidCallback? onStop;

  @override
  State<_LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends State<_LiveLocationCard> {
  final _map = MapController();
  LiveLocationView? _live;
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final v = await api.messaging.liveLocation(widget.shareId);
      if (!mounted) return;
      setState(() {
        _live = v;
        _loading = false;
      });
      // Keep the dot centred as it moves.
      try {
        _map.move(LatLng(v.latitude, v.longitude), _map.camera.zoom);
      } catch (_) {/* map not ready yet */}
      if (!v.active) _poll?.cancel(); // ended/expired — stop polling
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = _live;
    final lat = live?.latitude ?? widget.fallbackLat;
    final lng = live?.longitude ?? widget.fallbackLng;
    final active = live?.active ?? widget.initialActive;
    final point = (lat != null && lng != null) ? LatLng(lat, lng) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 230,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                children: [
                  if (point != null)
                    IgnorePointer(
                      child: FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: point,
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none),
                        ),
                        children: [
                          mapboxTileLayer(),
                          MarkerLayer(markers: [
                            Marker(
                              point: point,
                              width: 34,
                              height: 34,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: active
                                      ? const Color(0xFF2563EB)
                                      : scheme.outline,
                                  border: Border.all(
                                      color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    )
                  else
                    Container(
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.location_off),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF2563EB)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            active
                                ? Icons.share_location
                                : Icons.location_off,
                            size: 13,
                            color: Colors.white),
                        const SizedBox(width: 4),
                        Text(active ? 'LIVE' : 'Ended',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      active
                          ? (live?.expiresAt != null
                              ? 'Live until ${_hhmm(live!.expiresAt!.toLocal())}'
                              : 'Sharing live location')
                          : 'Live location ended',
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (widget.mine && active && widget.onStop != null)
                    TextButton(
                      onPressed: widget.onStop,
                      style: TextButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30)),
                      child: const Text('Stop'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the location picker returns: either a one-off place to send, or a
/// request to start sharing live location for [liveMinutes].
class _LocationResult {
  const _LocationResult.place(this.point, this.name) : liveMinutes = null;
  const _LocationResult.live(this.liveMinutes, this.point) : name = null;

  final LatLng point;
  final String? name;
  final int? liveMinutes;

  bool get isLive => liveMinutes != null;
}

/// WhatsApp-style location picker: a map on top, then "Share live location",
/// "Send your current location" with its accuracy, a place search, and a list
/// of nearby places to tap. Pops a [_LocationResult].
class _LocationPickerScreen extends StatefulWidget {
  const _LocationPickerScreen();

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  static const _fallback = LatLng(43.6532, -79.3832); // Toronto, if GPS denied
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();

  LatLng? _me; // current GPS fix, when available
  double _accuracyM = 0;
  LatLng _pin = _fallback; // the point the map is centred on / would send
  bool _pinMoved = false; // user tapped the map to choose a custom point
  bool _locating = true;

  List<Map<String, dynamic>> _nearby = const [];
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final fix = await currentFix();
    if (!mounted) return;
    setState(() {
      if (fix != null) {
        _me = fix.point;
        _accuracyM = fix.accuracyM;
        _pin = fix.point;
      }
      _locating = false;
    });
    if (fix != null) {
      _mapController.move(fix.point, 16);
      _loadNearby(fix.point);
    }
  }

  Future<void> _loadNearby(LatLng around) async {
    final places = await foursquareNearby(around);
    if (mounted) setState(() => _nearby = places);
  }

  void _recenter() {
    final me = _me;
    if (me == null) return;
    _mapController.move(me, 16);
    setState(() {
      _pin = me;
      _pinMoved = false;
    });
  }

  void _onMapTap(LatLng p) => setState(() {
        _pin = p;
        _pinMoved = true;
      });

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final found = await geocodePlaces(query, near: _me ?? _pin);
      if (mounted && _searchCtrl.text.trim() == query) {
        setState(() {
          _results = found;
          _searching = false;
        });
      }
    });
  }

  void _send(LatLng point, String name) =>
      Navigator.pop(context, _LocationResult.place(point, name));

  /// Lets the sharer pick how long to broadcast their live location, then pops
  /// a live result. This is the "how long to share" setting.
  Future<void> _chooseLiveDuration() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Share live location for',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            for (final opt in const [
              ('15 minutes', 15),
              ('1 hour', 60),
              ('8 hours', 480),
            ])
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(opt.$1),
                onTap: () => Navigator.pop(sheetCtx, opt.$2),
              ),
          ],
        ),
      ),
    );
    if (minutes == null || !mounted) return;
    Navigator.pop(context, _LocationResult.live(minutes, _me ?? _pin));
  }

  Widget _placeTile(Map<String, dynamic> p) {
    final lat = (p['lat'] as num?)?.toDouble();
    final lng = (p['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const SizedBox.shrink();
    final name = '${p['name'] ?? 'Place'}';
    final addr = '${p['full_address'] ?? ''}';
    return ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: addr.isEmpty
          ? null
          : Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _send(LatLng(lat, lng), name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showingResults = _searchCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Send location')),
      body: Column(
        children: [
          // Map with the current/selected point and a recenter button.
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 12,
                    onTap: (_, p) => _onMapTap(p),
                  ),
                  children: [
                    mapboxTileLayer(),
                    MarkerLayer(markers: [
                      Marker(
                        point: _pin,
                        width: 44,
                        height: 44,
                        child: Icon(Icons.location_pin,
                            color: scheme.error, size: 40),
                      ),
                    ]),
                  ],
                ),
                if (_locating)
                  const Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Text('Finding your location…'),
                        ),
                      ),
                    ),
                  ),
                if (_me != null)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'loc_recenter',
                      onPressed: _recenter,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
              ],
            ),
          ),
          // The action list.
          Expanded(
            flex: 6,
            child: Material(
              color: scheme.surface,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Live location: share a moving position for a set time.
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2563EB),
                      child: Icon(Icons.share_location, color: Colors.white),
                    ),
                    title: const Text('Share live location'),
                    subtitle: Text(_me == null
                        ? 'Waiting for your location…'
                        : 'Updates in real time for a set time'),
                    onTap: _me == null ? null : _chooseLiveDuration,
                  ),
                  const Divider(height: 1),
                  if (_me != null)
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF22C55E),
                        child: Icon(Icons.near_me, color: Colors.white),
                      ),
                      title: const Text('Send your current location'),
                      subtitle: Text(_accuracyM > 0
                          ? 'Accurate to ~${_accuracyM.round()} m'
                          : 'Using your device location'),
                      onTap: () => _send(_me!, 'Current location'),
                    ),
                  if (_pinMoved)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.error,
                        child:
                            const Icon(Icons.location_pin, color: Colors.white),
                      ),
                      title: const Text('Send this pinned location'),
                      subtitle: const Text('The point marked on the map'),
                      onTap: () => _send(_pin, 'Pinned location'),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search a place or address',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: showingResults
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (showingResults) ...[
                    if (_results.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('No places found.')),
                      )
                    else
                      for (final p in _results) _placeTile(p),
                  ] else ...[
                    if (_nearby.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text('NEARBY PLACES',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: scheme.outline)),
                      ),
                      for (final p in _nearby) _placeTile(p),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small composer for a poll message: a question and 2–6 options.
class _PollComposer extends StatefulWidget {
  const _PollComposer();

  @override
  State<_PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<_PollComposer> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final q = _question.text.trim();
    final opts =
        _options.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (q.isEmpty || opts.length < 2) {
      showInfo(context, 'Add a question and at least 2 options');
      return;
    }
    Navigator.pop(context, (q, opts));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a poll'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _question,
              decoration: const InputDecoration(
                  labelText: 'Question', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _options[i],
                  decoration: InputDecoration(
                      labelText: 'Option ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true),
                ),
              ),
            if (_options.length < 6)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add option'),
                  onPressed: () =>
                      setState(() => _options.add(TextEditingController())),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Send')),
      ],
    );
  }
}
