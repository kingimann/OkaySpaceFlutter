import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_settings_screen.dart';
import 'common.dart';

List<Map<String, dynamic>> _asMapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ??
        data['items'] ??
        data['users'] ??
        data['results'] ??
        data['data'];
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

/// Admin · Manage users: search anyone, then apply moderation and account
/// actions from a detail sheet.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  late Future<List<Map<String, dynamic>>> _users = _fetch('');

  /// Client-side list filter: 'all' | 'staff' | 'flagged'.
  String _filter = 'all';

  bool _matchesFilter(Map<String, dynamic> u) => switch (_filter) {
        'staff' => _s(u, ['role'], 'user') != 'user',
        'flagged' => u['banned'] == true ||
            u['suspended'] == true ||
            _s(u, ['suspended_until']).isNotEmpty,
        _ => true,
      };

  /// Set while the signed-in admin is unverified, enabling "Verify myself".
  String? _unverifiedSelfId;

  @override
  void initState() {
    super.initState();
    api.auth.me().then((me) {
      if (mounted && !me.verified) {
        setState(() => _unverifiedSelfId = me.userId);
      }
    }).catchError((_) {});
  }

  Future<void> _verifyMyself() async {
    final id = _unverifiedSelfId;
    if (id == null) return;
    try {
      await api.admin.updateUser(id, {'verified': true});
      if (mounted) {
        showInfo(context, 'You\'re verified');
        setState(() => _unverifiedSelfId = null);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<List<Map<String, dynamic>>> _fetch(String q) => api.admin
      .users(query: q.isEmpty ? null : q, limit: 100)
      .then(_asMapList);

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _users = _fetch(q.trim()));
    });
  }

  void _reload() {
    if (mounted) setState(() => _users = _fetch(_search.text.trim()));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Admin · Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Audit log',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminAuditScreen())),
          ),
        ],
      ),
      body: MaxWidth(
        child: Column(
          children: [
            if (_unverifiedSelfId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify myself'),
                    onPressed: _verifyMyself,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: _onQuery,
                decoration: InputDecoration(
                  hintText: 'Search by name, username, or email',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  for (final (id, label) in const [
                    ('all', 'All'),
                    ('staff', 'Staff'),
                    ('flagged', 'Banned/Suspended')
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == id,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _filter = id),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncList<Map<String, dynamic>>(
                future: _users,
                emptyMessage: 'No users found.',
                emptyIcon: Icons.person_search_outlined,
                builder: (context, all) {
                  // Filter here, not via a derived future: .then() in build
                  // hands the FutureBuilder a fresh Future every rebuild,
                  // flashing the skeleton.
                  final users = all.where(_matchesFilter).toList();
                  return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = users[i];
                    final name = _s(u, ['name', 'display_name'], 'User');
                    final role = _s(u, ['role'], 'user');
                    final banned = u['banned'] == true;
                    final suspended = u['suspended'] == true ||
                        _s(u, ['suspended_until']).isNotEmpty;
                    return ListTile(
                      leading: Avatar(
                          url: _s(u, ['picture', 'avatar']).isEmpty
                              ? null
                              : _s(u, ['picture', 'avatar']),
                          name: name),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (u['verified'] == true) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 15, color: Color(0xFF3B82F6)),
                          ],
                          if (role != 'user') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(role.toUpperCase(),
                                  style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                          _s(u, ['email', 'username', 'user_id']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: banned || suspended
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(banned ? 'Banned' : 'Suspended',
                                  style: TextStyle(
                                      color: scheme.error,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            )
                          : null,
                      onTap: () => _openUser(u),
                    );
                  },
                );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUser(Map<String, dynamic> u) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _UserActionsSheet(user: u, onChanged: _reload),
    );
  }
}

/// The per-user action sheet: every moderation/account control.
class _UserActionsSheet extends StatefulWidget {
  const _UserActionsSheet({required this.user, required this.onChanged});

  final Map<String, dynamic> user;
  final VoidCallback onChanged;

  @override
  State<_UserActionsSheet> createState() => _UserActionsSheetState();
}

class _UserActionsSheetState extends State<_UserActionsSheet> {
  late Map<String, dynamic> u = Map.of(widget.user);

  String get _id => _s(u, ['user_id', 'id']);
  String get _name => _s(u, ['name', 'display_name'], 'User');
  String get _role => _s(u, ['role'], 'user');
  bool get _banned =>
      u['banned'] == true || _s(u, ['suspended_until']).isNotEmpty ||
      u['suspended'] == true;

  Map<String, dynamic> get _restrictions =>
      u['restrictions'] is Map ? Map.from(u['restrictions'] as Map) : u;

  /// Runs an action optimistically: applies [apply] to the local copy,
  /// calls the API, reverts + shows the error on failure.
  Future<void> _act(Future<void> Function() op,
      {void Function(Map<String, dynamic>)? apply, String? ok}) async {
    final before = Map<String, dynamic>.from(u);
    if (apply != null) setState(() => apply(u));
    try {
      await op();
      if (ok != null && mounted) showInfo(context, ok);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => u = before);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _restrictions;
    final messagingOff = r['messaging_disabled'] == true;
    final marketOff = r['marketplace_disabled'] == true;
    final postingOff = r['posting_disabled'] == true;

    Widget action(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        dense: true,
        leading: Icon(icon, color: color ?? scheme.primary, size: 22),
        title: Text(label, style: TextStyle(color: color)),
        onTap: onTap,
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        children: [
          ListTile(
            leading: Avatar(
                url: _s(u, ['picture', 'avatar']).isEmpty
                    ? null
                    : _s(u, ['picture', 'avatar']),
                name: _name,
                radius: 24),
            title: Text(_name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17)),
            subtitle: Text('${_s(u, ['email', 'username'])} · role: $_role'),
          ),
          const Divider(),
          // Target values are captured BEFORE _act runs: the optimistic
          // apply mutates `u` first, so a lazy read inside the op closure
          // would send the server its own current value back (a no-op).
          action(
              u['verified'] == true
                  ? Icons.verified
                  : Icons.verified_outlined,
              u['verified'] == true ? 'Remove verification' : 'Verify', () {
            final next = u['verified'] != true;
            _act(() => api.admin.updateUser(_id, {'verified': next}),
                apply: (m) => m['verified'] = next);
          }),
          action(Icons.shield_outlined,
              _role == 'mod' ? 'Remove mod' : 'Make mod', () {
            final next = _role == 'mod' ? 'user' : 'mod';
            _act(() => api.admin.updateUser(_id, {'role': next}),
                apply: (m) => m['role'] = next);
          }),
          action(Icons.admin_panel_settings_outlined,
              _role == 'admin' ? 'Remove admin' : 'Make admin', () {
            final next = _role == 'admin' ? 'user' : 'admin';
            _act(() => api.admin.updateUser(_id, {'role': next}),
                apply: (m) => m['role'] = next);
          }),
          const Divider(),
          if (_banned)
            action(Icons.lock_open, 'Lift ban / suspension',
                () => _act(() => api.admin.unbanUser(_id), apply: (m) {
                      m['banned'] = false;
                      m['suspended'] = false;
                      m.remove('suspended_until');
                    }, ok: 'Lifted'))
          else ...[
            action(Icons.block, 'Ban…', _ban, color: scheme.error),
            action(Icons.timer_outlined, 'Suspend…', _suspend,
                color: scheme.error),
          ],
          action(
              messagingOff ? Icons.chat_bubble : Icons.speaker_notes_off,
              messagingOff ? 'Enable messaging' : 'Disable messaging',
              () => _toggleRestriction('messaging_disabled', !messagingOff)),
          action(
              postingOff ? Icons.post_add : Icons.do_not_disturb_on_outlined,
              postingOff ? 'Enable posting' : 'Disable posting',
              () => _toggleRestriction('posting_disabled', !postingOff)),
          action(
              marketOff ? Icons.storefront : Icons.remove_shopping_cart_outlined,
              marketOff ? 'Enable marketplace' : 'Disable marketplace',
              () => _toggleRestriction('marketplace_disabled', !marketOff)),
          const Divider(),
          action(Icons.account_balance_wallet_outlined, 'Set wallet balance…',
              _setWallet),
          action(Icons.receipt_long_outlined, 'View transactions…',
              _transactions),
          action(Icons.add_card_outlined, 'Re-add lost transaction…',
              _addTransaction),
          action(Icons.military_tech_outlined, 'Assign badges…', _badges),
          const Divider(),
          action(Icons.delete_forever_outlined, 'Remove account…', _remove,
              color: scheme.error),
        ],
      ),
    );
  }

  Future<void> _toggleRestriction(String key, bool value) => _act(
      () => api.admin.setRestrictions(_id, {key: value}),
      apply: (m) => m[key] = value,
      ok: 'Updated');

  Future<void> _ban() async {
    final reason = await promptText(context,
        title: 'Ban $_name', hint: 'Reason (shown in the audit log)',
        action: 'Ban');
    if (reason == null || !mounted) return;
    await _act(() => api.admin.banUser(_id, reason: reason),
        apply: (m) => m['banned'] = true, ok: 'Banned');
  }

  Future<void> _suspend() async {
    var days = 3;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text('Suspend $_name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, d) in const [
                    ('1 day', 1),
                    ('3 days', 3),
                    ('1 week', 7),
                    ('1 month', 30)
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: days == d,
                      onSelected: (_) => setDialog(() => days = d),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                    labelText: 'Reason', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Suspend')),
          ],
        ),
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || !mounted) return;
    await _act(
        () => api.admin.suspendUser(_id,
            days: days, reason: reason.isEmpty ? null : reason),
        apply: (m) => m['suspended'] = true,
        ok: 'Suspended for $days day${days == 1 ? '' : 's'}');
  }

  Future<void> _setWallet() async {
    final raw = await promptText(context,
        title: 'Set wallet balance',
        hint: 'New balance (USD)',
        action: 'Set');
    final amount = num.tryParse(raw ?? '');
    if (amount == null || !amount.isFinite || !mounted) return;
    await _act(() => api.admin.setWallet(_id, {'amount': amount}),
        ok: 'Balance set to \$${amount.toStringAsFixed(2)}');
  }

  Future<void> _transactions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _UserTransactionsSheet(userId: _id, name: _name),
    );
  }

  Future<void> _addTransaction() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var kind = 'topup';
    var adjust = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Re-add transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, k) in const [
                    ('Top-up', 'topup'),
                    ('Received', 'received'),
                    ('Sent', 'sent'),
                    ('Cash-out', 'cashout')
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: kind == k,
                      onSelected: (_) => setDialog(() => kind = k),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Amount', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder()),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Adjust balance'),
                value: adjust,
                onChanged: (v) => setDialog(() => adjust = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    final amount = num.tryParse(amountCtrl.text.trim());
    final note = noteCtrl.text.trim();
    amountCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || amount == null || !amount.isFinite || !mounted) return;
    await _act(
        () => api.admin.addTransaction(_id, {
              'kind': kind,
              'amount': amount,
              if (note.isNotEmpty) 'note': note,
              'adjust': adjust,
            }),
        ok: 'Transaction added');
  }

  Future<void> _badges() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AssignBadgesSheet(userId: _id),
    );
  }

  Future<void> _remove() async {
    if (!await adminConfirm(context, 'Remove $_name',
        'Permanently removes this account and its content. This cannot be undone.',
        action: 'Remove account', destructive: true)) {
      return;
    }
    if (!mounted) return;
    try {
      await api.admin.deleteUser(_id);
      if (mounted) {
        showInfo(context, 'Account removed');
        Navigator.pop(context);
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}

/// A user's transactions with per-row edit/delete (admin repair tools).
class _UserTransactionsSheet extends StatefulWidget {
  const _UserTransactionsSheet({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  State<_UserTransactionsSheet> createState() =>
      _UserTransactionsSheetState();
}

class _UserTransactionsSheetState extends State<_UserTransactionsSheet> {
  late Future<List<Map<String, dynamic>>> _txns = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() => api.admin
      .userTransactions(widget.userId)
      .then((d) => _asMapList(d, 'transactions'));

  void _reload() => setState(() => _txns = _fetch());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${widget.name} · transactions',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: AsyncList<Map<String, dynamic>>(
              future: _txns,
              emptyMessage: 'No transactions.',
              emptyIcon: Icons.receipt_long_outlined,
              builder: (context, items) => ListView.separated(
                controller: controller,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = items[i];
                  final id = _s(t, ['id', 'ref', 'reference']);
                  final amount =
                      num.tryParse(_s(t, ['amount'], '0')) ?? 0;
                  return ListTile(
                    dense: true,
                    title: Text(
                        '${_s(t, ['type', 'kind'], 'txn')} · \$${amount.toStringAsFixed(2)}'),
                    subtitle: Text(
                        [
                          _s(t, ['note', 'counterparty_name']),
                          _s(t, ['created_at']),
                        ].where((x) => x.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _edit(id, t),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: scheme.error),
                          onPressed: () => _delete(id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(String id, Map<String, dynamic> t) async {
    final raw = await promptText(context,
        title: 'Edit amount',
        hint: 'New amount (was ${_s(t, ['amount'], '0')})',
        action: 'Save');
    final amount = num.tryParse(raw ?? '');
    if (amount == null || !amount.isFinite || !mounted) return;
    try {
      await api.admin.editTransaction(widget.userId, id, {'amount': amount});
      if (mounted) {
        showInfo(context, 'Transaction updated');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(String id) async {
    if (!await adminConfirm(context, 'Delete transaction',
        'Delete this transaction and adjust the balance accordingly?',
        action: 'Delete', destructive: true)) {
      return;
    }
    if (!mounted) return;
    try {
      await api.admin.deleteTransaction(widget.userId, id, adjust: true);
      if (mounted) {
        showInfo(context, 'Transaction deleted');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}

/// Toggle custom badges on a user.
class _AssignBadgesSheet extends StatefulWidget {
  const _AssignBadgesSheet({required this.userId});

  final String userId;

  @override
  State<_AssignBadgesSheet> createState() => _AssignBadgesSheetState();
}

class _AssignBadgesSheetState extends State<_AssignBadgesSheet> {
  late final Future<List<Map<String, dynamic>>> _badges =
      api.admin.listBadges().then((d) => _asMapList(d, 'badges'));
  final Set<String> _busy = {};
  final Set<String> _has = {};
  bool _loadedUser = false;

  @override
  void initState() {
    super.initState();
    api.users.publicProfile(widget.userId).then((u) {
      final list = u.raw['badges'];
      if (mounted) {
        setState(() {
          if (list is List) {
            _has.addAll(list.map((b) =>
                b is Map ? '${b['id'] ?? b['badge_id'] ?? ''}' : '$b'));
          }
          _loadedUser = true;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loadedUser = true);
    });
  }

  Future<void> _toggle(String badgeId) async {
    final had = _has.contains(badgeId);
    setState(() {
      _busy.add(badgeId);
      had ? _has.remove(badgeId) : _has.add(badgeId);
    });
    try {
      await api.admin.grantBadge(widget.userId,
          {'badge_id': badgeId, 'action': had ? 'remove' : 'add'});
    } catch (e) {
      if (mounted) {
        setState(() => had ? _has.add(badgeId) : _has.remove(badgeId));
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(badgeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AsyncList<Map<String, dynamic>>(
        future: _badges,
        emptyMessage: 'No custom badges yet.\nCreate them in Custom badges.',
        emptyIcon: Icons.military_tech_outlined,
        builder: (context, badges) => ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('Assign badges',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            if (!_loadedUser)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final b in badges)
                CheckboxListTile(
                  secondary: Text(_s(b, ['icon'], '🏅'),
                      style: const TextStyle(fontSize: 20)),
                  title: Text(_s(b, ['label', 'name'], 'Badge')),
                  value: _has.contains(_s(b, ['id', 'badge_id'])),
                  onChanged: _busy.contains(_s(b, ['id', 'badge_id']))
                      ? null
                      : (_) => _toggle(_s(b, ['id', 'badge_id'])),
                ),
          ],
        ),
      ),
    );
  }
}

/// Admin · Audit log: read-only list of every admin action.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  late Future<List<Map<String, dynamic>>> _log = _fetch();
  final _query = TextEditingController();

  bool _matches(Map<String, dynamic> e) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      _s(e, ['admin_name', 'admin']),
      _s(e, ['action', 'type']),
      _s(e, ['target_name', 'target', 'user_name']),
      _s(e, ['detail', 'reason', 'note']),
    ].any((v) => v.toLowerCase().contains(q));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch() =>
      api.admin.auditLog(limit: 200).then((d) => _asMapList(d, 'entries'));

  Future<void> _reload() async {
    setState(() => _log = _fetch());
    try {
      await _log;
    } catch (_) {}
  }

  Color _dotColor(String action) {
    final a = action.toLowerCase();
    if (a.contains('ban') || a.contains('remove') || a.contains('delete')) {
      return const Color(0xFFEF4444);
    }
    if (a.contains('suspend') || a.contains('disable')) {
      return const Color(0xFFF59E0B);
    }
    if (a.contains('verif') || a.contains('badge')) {
      return const Color(0xFF3B82F6);
    }
    return const Color(0xFF22C55E);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Activity log')),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Filter by admin, action, target, or reason',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _log,
            emptyMessage: 'No admin activity yet.',
            emptyIcon: Icons.history,
            builder: (context, all) {
              final entries = all.where(_matches).toList();
              return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = entries[i];
                final action = _s(e, ['action', 'type'], 'action');
                final when = DateTime.tryParse(_s(e, ['created_at', 'at']));
                final detail = _s(e, ['detail', 'reason', 'note']);
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                        color: _dotColor(action), shape: BoxShape.circle),
                  ),
                  title: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: _s(e, ['admin_name', 'admin'], 'Admin'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: ' $action '),
                    TextSpan(
                        text: _s(e, ['target_name', 'target', 'user_name']),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ])),
                  subtitle: detail.isEmpty ? null : Text('“$detail”'),
                  trailing: when == null
                      ? null
                      : Text(shortAgo(when),
                          style:
                              TextStyle(color: scheme.outline, fontSize: 12)),
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
