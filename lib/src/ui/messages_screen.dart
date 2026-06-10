import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'call_screen.dart';
import 'common.dart';

/// List of the current user's conversations.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<ConversationView>> _conversations;

  @override
  void initState() {
    super.initState();
    _conversations = api.messaging.conversations();
  }

  Future<void> _reload() async {
    setState(() => _conversations = api.messaging.conversations());
    await _conversations;
  }

  Future<void> _newChat() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const _NewChatScreen()));
    _reload();
  }

  String _title(ConversationView c) {
    if (c.name != null && c.name!.isNotEmpty) return c.name!;
    if (c.otherUser != null) return c.otherUser!.name;
    if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
    return 'Conversation';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        child: const Icon(Icons.edit_square),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<ConversationView>(
          future: _conversations,
          loading: const ListSkeleton(),
          emptyMessage: 'No conversations yet.',
          emptyIcon: Icons.forum_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = items[i];
              final title = _title(c);
              return _ConversationTile(
                conversation: c,
                title: title,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(conversation: c, title: title),
                  ));
                  _reload();
                },
              );
            },
          ),
        ),
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
  });

  final ConversationView conversation;
  final String title;
  final VoidCallback onTap;

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
  late Future<List<Message>> _messages;
  final _input = TextEditingController();
  bool _sending = false;

  String get _convId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _messages = api.messaging.messages(_convId);
    api.messaging.markRead(_convId).ignore();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _messages = api.messaging.messages(_convId));
    await _messages;
  }

  void _call({bool video = false}) {
    CallScreen.open(
      context,
      conversationId: _convId,
      title: widget.title,
      avatarUrl: widget.conversation.avatar ??
          widget.conversation.otherUser?.picture,
      video: video,
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await api.messaging.sendText(_convId, text);
      _input.clear();
      await _reload();
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
      await _reload();
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
                ],
              ),
            ),
            const Divider(height: 1),
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
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(
                url: widget.conversation.avatar ?? other?.picture,
                name: widget.title,
                radius: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title,
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
                                : Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
          ],
        ),
        actions: [
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
          Expanded(
            child: AsyncList<Message>(
              future: _messages,
              emptyMessage: 'Say hello 👋',
              emptyIcon: Icons.waving_hand_outlined,
              builder: (context, items) => ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  // Newest first when reversed.
                  final msg = items[items.length - 1 - i];
                  // In a direct chat, anything not sent by the other person is
                  // ours. Group chats fall back to left-aligned.
                  final otherId = widget.conversation.otherUser?.userId;
                  final mine = otherId != null && msg.senderId != otherId;
                  return _MessageBubble(
                    message: msg,
                    mine: mine,
                    onLongPress:
                        msg.deleted ? null : () => _messageActions(msg, mine),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
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
      {required this.message, this.mine = false, this.onLongPress});

  final Message message;
  final bool mine;
  final VoidCallback? onLongPress;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = message.deleted
        ? 'Message deleted'
        : (message.text ?? '[${message.type}]');
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
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
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
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      style: TextStyle(
                          color: fg,
                          fontStyle: message.deleted
                              ? FontStyle.italic
                              : FontStyle.normal)),
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
      appBar: AppBar(
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
