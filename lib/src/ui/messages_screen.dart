import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
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
      body: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<ConversationView>(
          future: _conversations,
          emptyMessage: 'No conversations yet.',
          emptyIcon: Icons.forum_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = items[i];
              final title = _title(c);
              return ListTile(
                leading: Avatar(
                    url: c.avatar ?? c.otherUser?.picture, name: title),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: c.lastMessage?.text != null
                    ? Text(c.lastMessage!.text!,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: c.unreadCount > 0
                    ? Badge(label: Text('${c.unreadCount}'))
                    : (c.lastMessageAt != null
                        ? Text(shortAgo(c.lastMessageAt!),
                            style: Theme.of(context).textTheme.bodySmall)
                        : null),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
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
                  return _MessageBubble(message: msg, mine: mine);
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
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.mine = false});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = message.deleted
        ? 'Message deleted'
        : (message.text ?? '[${message.type}]');
    final bg = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;
    const radius = Radius.circular(18);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
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
            Text(shortAgo(message.createdAt),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: fg.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}
