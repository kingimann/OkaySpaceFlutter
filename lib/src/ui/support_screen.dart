import 'package:flutter/material.dart';

import 'common.dart';

/// Coerces a dynamic API payload into a list of maps, tolerating either a bare
/// list or an object wrapping the list under a common key.
List<Map<String, dynamic>> _asMapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ?? data['items'] ?? data['results'] ?? data['data'];
  }
  if (list is List) {
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

String _str(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return fallback;
}

/// Help-desk: lists the user's support tickets and lets them open a new one.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late Future<List<Map<String, dynamic>>> _tickets;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _tickets = api.support.tickets().then((d) => _asMapList(d, 'tickets'));
  }

  Future<void> _reload() async {
    setState(_load);
    await _tickets;
  }

  Future<void> _newTicket() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _NewTicketDialog(),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        icon: const Icon(Icons.add),
        label: const Text('New ticket'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Map<String, dynamic>>(
          future: _tickets,
          loading: const ListSkeleton(),
          emptyMessage: 'No support tickets.\nTap “New ticket” to get help.',
          emptyIcon: Icons.support_agent_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = items[i];
              final id = _str(t, ['id', 'ticket_id']);
              final subject = _str(t, ['subject', 'title'], 'Ticket');
              final status = _str(t, ['status'], 'open');
              return ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: Text(subject),
                subtitle: Text('Status: $status'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TicketDetailScreen(ticketId: id, subject: subject),
                )),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// A single ticket's thread plus a reply box.
class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen(
      {super.key, required this.ticketId, required this.subject});

  final String ticketId;
  final String subject;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  late Future<Map<String, dynamic>> _ticket;
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _ticket = api.support.ticket(widget.ticketId);
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _ticket = api.support.ticket(widget.ticketId));
    await _ticket;
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await api.support.reply(widget.ticketId, text);
      _reply.clear();
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
      appBar: OkayAppBar(title: Text(widget.subject)),
      body: MaxWidth(
        child: Column(
        children: [
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _ticket,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return CenteredMessage(
                      message: messageFor(snapshot.error),
                      icon: Icons.error_outline);
                }
                final ticket = snapshot.data ?? const {};
                final messages =
                    _asMapList(ticket['messages'] ?? ticket, 'messages');
                if (messages.isEmpty) {
                  return const CenteredMessage(
                      message: 'No messages on this ticket yet.',
                      icon: Icons.forum_outlined);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final staff = (m['is_staff'] == true) ||
                        (m['staff'] == true) ||
                        _str(m, ['author', 'from', 'sender']).toLowerCase() ==
                            'staff';
                    final body = _str(m, ['message', 'body', 'text']);
                    return Align(
                      alignment:
                          staff ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: staff
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                              : Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(staff ? 'Support' : 'You',
                                style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: 2),
                            Text(body),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
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
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Reply to support',
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

class _NewTicketDialog extends StatefulWidget {
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await api.support.createTicket(
        subject: _subject.text.trim(),
        message: _message.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New support ticket'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _subject,
            decoration: const InputDecoration(
                labelText: 'Subject', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'How can we help?', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit'),
        ),
      ],
    );
  }
}
