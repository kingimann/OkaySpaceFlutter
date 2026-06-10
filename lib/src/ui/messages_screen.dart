import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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

  String get _convId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _fetch();
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
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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
          if (identical(row, _unreadMarker)) return const _UnreadDivider();
          final msg = row as Message;
          final mine = _isMine(msg);
          final key = _msgKeys.putIfAbsent(msg.id, GlobalKey.new);
          final bubble = _MessageBubble(
            message: msg,
            mine: mine,
            highlight: _highlightId == msg.id,
            replyTo: msg.replyToId != null ? byId[msg.replyToId] : null,
            onTapReply: msg.replyToId != null
                ? () => _jumpTo(msg.replyToId!)
                : null,
            senderName:
                (isGroup && !mine && !msg.deleted) ? _senderName(msg.senderId) : null,
            receipt: (!isGroup &&
                    mine &&
                    msg.id == lastMineId &&
                    widget.conversation.receiptsEnabled)
                ? _receipt(msg)
                : null,
            onLongPress: msg.deleted ? null : () => _messageActions(msg, mine),
            onDoubleTap: msg.deleted
                ? null
                : () => _run(
                    () => api.messaging.reactToMessage(_convId, msg.id, '❤️')),
          );
          if (msg.deleted) return KeyedSubtree(key: key, child: bubble);
          // Swipe a message to the right to reply to it.
          return KeyedSubtree(
            key: key,
            child: Dismissible(
              key: ValueKey('swipe-${msg.id}'),
              direction: DismissDirection.startToEnd,
              dismissThresholds: const {DismissDirection.startToEnd: 0.2},
              confirmDismiss: (_) async {
                setState(() => _replyTo = msg);
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
      _stopTyping();
      if (mounted) setState(() => _replyTo = null);
      await _fetch(silent: true);
      _scrollToBottom();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      appBar: OkayAppBar(
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
                  Text(_chatTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
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
                _buildMessages(),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    tooltip: 'Send photo',
                    onPressed: _sending ? null : _attachImage,
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
      this.onLongPress,
      this.onDoubleTap,
      this.onTapReply,
      this.replyTo,
      this.senderName,
      this.receipt});

  final Message message;
  final bool mine;

  /// Briefly true when this message was jumped-to from a reply quote.
  final bool highlight;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  /// Tapped the reply quote — jumps to the original message.
  final VoidCallback? onTapReply;

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
        : (message.text ?? (hasMedia ? '' : typeLabel));
    // Outgoing bubble = a dark tint of the current accent (teal by default,
    // matching okayspace.ca's WhatsApp-style chat).
    final bg = mine
        ? HSLColor.fromColor(scheme.primary).withLightness(0.22).toColor()
        : scheme.surfaceContainerHighest;
    final fg = mine ? OkayColors.textPrimary : scheme.onSurface;
    const radius = Radius.circular(18);
    final reactions = _reactionChips();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
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
                  if (bodyText.isNotEmpty)
                    message.deleted
                        ? Text(bodyText,
                            style: TextStyle(
                                color: fg, fontStyle: FontStyle.italic))
                        : LinkedText(bodyText, style: TextStyle(color: fg)),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
              Container(
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
          ],
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
