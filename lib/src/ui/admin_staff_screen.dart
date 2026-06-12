import 'package:flutter/material.dart';

import 'admin_settings_screen.dart';
import 'common.dart';

List<Map<String, dynamic>> _asMapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ??
        data['items'] ??
        data['verifications'] ??
        data['calls'] ??
        data['tickets'] ??
        data['results'];
  }
  if (list is List) {
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

String _s(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return fallback;
}

void _lightbox(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(child: InteractiveViewer(child: Image.network(url))),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Staff · Roadside verifications: manual review of document submissions.
class AdminRoadsideScreen extends StatefulWidget {
  const AdminRoadsideScreen({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  State<AdminRoadsideScreen> createState() => _AdminRoadsideScreenState();
}

class _AdminRoadsideScreenState extends State<AdminRoadsideScreen> {
  late Future<List<Map<String, dynamic>>> _items = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() =>
      api.admin.roadsideVerifications().then(_asMapList);

  Future<void> _reload() async {
    setState(() => _items = _fetch());
    try {
      await _items;
    } catch (_) {}
  }

  Future<void> _decide(String id, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await promptText(context,
          title: 'Reject verification',
          hint: 'Reason (shown to the member)',
          action: 'Reject');
      if (reason == null || !mounted) return;
    }
    try {
      await api.admin.decideRoadsideVerification(id, {
        'approved': approve,
        if (reason != null) 'reason': reason,
      });
      if (mounted) {
        showInfo(context, approve ? 'Approved' : 'Rejected');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Roadside verifications'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.call_outlined),
              tooltip: 'Roadside calls',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminRoadsideCallsScreen())),
            ),
        ],
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _items,
            emptyMessage: 'No pending verifications.',
            emptyIcon: Icons.fact_check_outlined,
            builder: (context, items) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final v in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Avatar(
                                  url: _s(v, ['picture', 'avatar']).isEmpty
                                      ? null
                                      : _s(v, ['picture', 'avatar']),
                                  name: _s(v, ['name', 'user_name'], 'User')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(_s(v, ['name', 'user_name'], 'User'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(_s(v, ['email']),
                                        style: TextStyle(
                                            color: scheme.outline,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_s(v, ['vehicle']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Vehicle: ${_s(v, ['vehicle'])}'),
                            ),
                          if (_s(v, ['note']).isNotEmpty)
                            Text('Note: ${_s(v, ['note'])}',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 13)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final (label, key) in const [
                                ('Insurance', 'insurance_url'),
                                ('Ownership', 'ownership_url')
                              ])
                                if (_s(v, [key]).isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 10),
                                    child: Column(
                                      children: [
                                        InkWell(
                                          onTap: () => _lightbox(
                                              context, _s(v, [key])),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.network(
                                                _s(v, [key]),
                                                width: 90,
                                                height: 64,
                                                fit: BoxFit.cover),
                                          ),
                                        ),
                                        Text(label,
                                            style: const TextStyle(
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: scheme.error),
                                  onPressed: () =>
                                      _decide(_s(v, ['id']), false),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      _decide(_s(v, ['id']), true),
                                  child: const Text('Approve'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Admin · Roadside calls: create, search, and bulk-erase service calls.
class AdminRoadsideCallsScreen extends StatefulWidget {
  const AdminRoadsideCallsScreen({super.key});

  @override
  State<AdminRoadsideCallsScreen> createState() =>
      _AdminRoadsideCallsScreenState();
}

class _AdminRoadsideCallsScreenState extends State<AdminRoadsideCallsScreen> {
  late Future<List<Map<String, dynamic>>> _calls = _fetch();
  final _date = TextEditingController();
  final _callNo = TextEditingController();

  Future<List<Map<String, dynamic>>> _fetch({String? date, String? callNo}) =>
      api.admin
          .roadsideCalls(date: date, callNumber: callNo)
          .then(_asMapList);

  void _search() => setState(() => _calls = _fetch(
        date: _date.text.trim().isEmpty ? null : _date.text.trim(),
        callNo: _callNo.text.trim().isEmpty ? null : _callNo.text.trim(),
      ));

  @override
  void dispose() {
    _date.dispose();
    _callNo.dispose();
    super.dispose();
  }

  Future<void> _erase({required bool testOnly}) async {
    if (!await adminConfirm(
        context,
        testOnly ? 'Erase test calls' : 'Erase ALL calls',
        testOnly
            ? 'Removes every call created as a test.'
            : 'Removes every roadside call, real and test. This cannot be undone.',
        action: 'Erase',
        destructive: true)) {
      return;
    }
    try {
      await api.admin.eraseRoadsideCalls(testOnly: testOnly);
      if (mounted) {
        showInfo(context, 'Erased');
        _search();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _create({required bool isTest}) async {
    final name = await promptText(context,
        title: isTest ? 'Test call · caller name' : 'Real call · caller name',
        hint: 'Caller name',
        action: 'Next');
    if (name == null || !mounted) return;
    final place = await promptText(context,
        title: 'Place / address', hint: 'Where is the vehicle?',
        action: 'Create');
    if (place == null || !mounted) return;
    try {
      final res = await api.admin.createRoadsideCall({
        'service': 'tow',
        'caller_name': name,
        'place': place,
        'is_test': isTest,
      });
      if (mounted) {
        showInfo(
            context,
            isTest
                ? 'Test call created'
                : 'Call #${res['call_number'] ?? res['number'] ?? '?'} created');
        _search();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Roadside calls')),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _date,
                      decoration: const InputDecoration(
                          labelText: 'Date (YYYY-MM-DD)',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _callNo,
                      decoration: const InputDecoration(
                          labelText: 'Call #',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.search), onPressed: _search),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                      label: const Text('Test call'),
                      onPressed: () => _create(isTest: true)),
                  ActionChip(
                      label: const Text('Real call'),
                      onPressed: () => _create(isTest: false)),
                  ActionChip(
                      label: const Text('Erase test calls'),
                      onPressed: () => _erase(testOnly: true)),
                  ActionChip(
                      label: Text('Erase all',
                          style: TextStyle(color: scheme.error)),
                      onPressed: () => _erase(testOnly: false)),
                ],
              ),
            ),
            Expanded(
              child: AsyncList<Map<String, dynamic>>(
                future: _calls,
                emptyMessage: 'No roadside calls.',
                emptyIcon: Icons.car_crash_outlined,
                builder: (context, calls) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in calls)
                      Card(
                        child: ListTile(
                          title: Text(
                              '#${_s(c, ['call_number', 'number'], '?')} · ${_s(c, ['service'], 'call')}'
                              '${c['is_test'] == true ? ' · TEST' : ''}'),
                          subtitle: Text(
                              [
                                _s(c, ['caller_name', 'requester_name']),
                                _s(c, ['place', 'address']),
                                _s(c, ['status']),
                                if (_s(c, ['price', 'amount']).isNotEmpty)
                                  '\$${_s(c, ['price', 'amount'])}',
                              ].where((x) => x.isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: scheme.error),
                            onPressed: () async {
                              if (!await adminConfirm(context, 'Delete call',
                                  'Delete this roadside call?',
                                  action: 'Delete', destructive: true)) {
                                return;
                              }
                              try {
                                await api.admin
                                    .deleteRoadsideCall(_s(c, ['id']));
                                if (context.mounted) _search();
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
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

/// Staff · Support queue: tickets across the platform, filterable by status.
class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  String _filter = 'open';
  late Future<List<Map<String, dynamic>>> _tickets = _fetch();

  /// Selected ticket ids while in bulk-select mode (long-press to start).
  final Set<String> _selected = {};
  bool _bulkBusy = false;

  Future<void> _bulkSetStatus(String status) async {
    final ids = _selected.toList();
    setState(() => _bulkBusy = true);
    var done = 0;
    try {
      for (final id in ids) {
        await api.support.setStatus(id, status);
        done++;
      }
      if (mounted) showInfo(context, 'Marked $done $status');
    } catch (e) {
      if (mounted) {
        showError(context, done > 0 ? '$done of ${ids.length} updated — $e' : e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _bulkBusy = false;
          _selected.clear();
        });
        _reload();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetch() => api.admin
      .supportTickets(status: _filter == 'all' ? null : _filter)
      .then(_asMapList);

  void _reload() => setState(() => _tickets = _fetch());

  Color _statusColor(String status, ColorScheme scheme) =>
      switch (status.toLowerCase()) {
        'open' => const Color(0xFF22C55E),
        'resolved' => const Color(0xFF3B82F6),
        'closed' => scheme.outline,
        _ => const Color(0xFFF59E0B),
      };

  Future<void> _open(Map<String, dynamic> t) async {
    final id = _s(t, ['id', 'ticket_id']);
    // Staff thread: show messages + reply + status controls.
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TicketThreadSheet(ticketId: id),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(_selected.isEmpty
            ? 'Support queue'
            : '${_selected.length} selected'),
        actions: [
          if (_selected.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.task_alt),
              tooltip: 'Mark resolved',
              onPressed: _bulkBusy ? null : () => _bulkSetStatus('resolved'),
            ),
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Mark closed',
              onPressed: _bulkBusy ? null : () => _bulkSetStatus('closed'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel selection',
              onPressed: () => setState(_selected.clear),
            ),
          ],
        ],
      ),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  for (final f in const ['open', 'all', 'resolved', 'closed'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f[0].toUpperCase() + f.substring(1)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() {
                          _filter = f;
                          // A new filter hides rows; keeping the old
                          // selection would bulk-act on invisible tickets.
                          _selected.clear();
                          _tickets = _fetch();
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncList<Map<String, dynamic>>(
                future: _tickets,
                emptyMessage: 'No tickets.',
                emptyIcon: Icons.support_agent_outlined,
                builder: (context, tickets) => ListView.separated(
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = tickets[i];
                    final status = _s(t, ['status'], 'open');
                    final id = _s(t, ['id', 'ticket_id']);
                    final when =
                        DateTime.tryParse(_s(t, ['created_at', 'updated_at']));
                    return ListTile(
                      selected: _selected.contains(id),
                      leading: _selected.isEmpty
                          ? null
                          : Checkbox(
                              value: _selected.contains(id),
                              onChanged: (_) => setState(() =>
                                  _selected.contains(id)
                                      ? _selected.remove(id)
                                      : _selected.add(id)),
                            ),
                      onLongPress: () =>
                          setState(() => _selected.add(id)),
                      title: Text(_s(t, ['subject'], 'Ticket'),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          [
                            _s(t, ['user_name', 'name']),
                            _s(t, ['category']),
                            if (when != null) shortAgo(when),
                          ].where((x) => x.isNotEmpty).join(' · ')),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(status, scheme)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(status,
                            style: TextStyle(
                                color: _statusColor(status, scheme),
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      onTap: _selected.isEmpty
                          ? () => _open(t)
                          : () => setState(() => _selected.contains(id)
                              ? _selected.remove(id)
                              : _selected.add(id)),
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

/// Staff view of one ticket: thread, reply box, and status buttons.
class _TicketThreadSheet extends StatefulWidget {
  const _TicketThreadSheet({required this.ticketId});

  final String ticketId;

  @override
  State<_TicketThreadSheet> createState() => _TicketThreadSheetState();
}

class _TicketThreadSheetState extends State<_TicketThreadSheet> {
  late Future<Map<String, dynamic>> _ticket = api.support.ticket(widget.ticketId);
  final _reply = TextEditingController();
  bool _busy = false;

  void _reload() =>
      setState(() => _ticket = api.support.ticket(widget.ticketId));

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await api.support.reply(widget.ticketId, text);
      _reply.clear();
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await api.support.setStatus(widget.ticketId, status);
      if (mounted) {
        showInfo(context, 'Marked $status');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _ticket,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final t = snapshot.data!;
            final messages = _asMapList(t['messages'] ?? t['thread']);
            return Column(
              children: [
                ListTile(
                  title: Text(_s(t, ['subject'], 'Ticket'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${_s(t, ['user_name', 'name'])} · ${_s(t, ['status'], 'open')}'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final st in const ['open', 'resolved', 'closed'])
                        ActionChip(
                            label: Text('Mark $st'),
                            onPressed: () => _setStatus(st)),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in messages)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${_s(m, ['sender_name', 'from', 'author'], 'User')}'
                                  '${m['is_staff'] == true ? ' · staff' : ''}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.outline)),
                              Text(_s(m, ['message', 'text', 'body'])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reply,
                          decoration: const InputDecoration(
                              hintText: 'Reply as staff…',
                              isDense: true,
                              border: OutlineInputBorder()),
                        ),
                      ),
                      IconButton(
                        icon: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
