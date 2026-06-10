import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'pay_qr_screen.dart';

String _money(num amount, String currency) =>
    '$currency ${amount.toStringAsFixed(2)}';

/// Reads the first non-empty string from [keys] in [m].
String _pick(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return fallback;
}

List<Map<String, dynamic>> _mapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ?? data['items'] ?? data['requests'] ?? data['results'] ??
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

/// Wallet: balance, earnings, transactions, money requests and transfers.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<WalletSummary> _summary;
  late Future<List<Map<String, dynamic>>> _requests;
  late Future<List<Map<String, dynamic>>> _transfers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summary = api.wallet.summary();
    _requests = api.wallet.moneyRequests().then((d) => _mapList(d, 'requests'));
    _transfers =
        api.wallet.transfers().then((d) => _mapList(d, 'transfers'));
  }

  Future<void> _reload() async {
    setState(_load);
    await _summary;
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true) _reload();
  }

  Future<void> _changeCurrency() async {
    final w = await _summary;
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Display currency',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final c in const ['USD', 'CAD', 'EUR', 'GBP', 'NGN', 'INR'])
              ListTile(
                title: Text(c),
                trailing: c == w.currency ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == w.currency) return;
    try {
      await api.wallet.setCurrency(picked);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _security() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _SecurityDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wallet'),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code),
              tooltip: 'Pay by QR',
              onPressed: () => _push(const PayQrScreen()),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'currency') _changeCurrency();
                if (v == 'security') _security();
                if (v == 'topups') _push(const TopUpHistoryScreen());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'currency', child: Text('Change currency')),
                PopupMenuItem(value: 'security', child: Text('Transfer security')),
                PopupMenuItem(value: 'topups', child: Text('Top-up history')),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Requests'),
              Tab(text: 'Transfers'),
            ],
          ),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [_overview(), _requestsTab(), _transfersTab()],
          ),
        ),
      ),
    );
  }

  Widget _overview() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<WalletSummary>(
        future: _summary,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CenteredMessage(
                message: messageFor(snapshot.error),
                icon: Icons.error_outline,
                onRetry: _reload);
          }
          final w = snapshot.data!;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _balanceCard(w, scheme),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _StatCard(
                          label: 'Earned',
                          value: _money(w.totalEarned, w.currency),
                          icon: Icons.trending_up,
                          color: const Color(0xFF22C55E))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                          label: 'Spent',
                          value: _money(w.totalSpent, w.currency),
                          icon: Icons.trending_down,
                          color: const Color(0xFFF43F5E))),
                ],
              ),
              const SizedBox(height: 24),
              Text('Recent activity',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (w.recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No transactions yet.')),
                )
              else
                ...w.recent.map((t) => _TxnTile(txn: t)),
            ],
          );
        },
      ),
    );
  }

  Widget _balanceCard(WalletSummary w, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, darken(scheme.primary, 0.22)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet,
                  color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(width: 8),
              Text('Available balance',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
            ],
          ),
          const SizedBox(height: 10),
          Text(_money(w.balance, w.currency),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              _action('Add', Icons.add, () => _push(const AddMoneyScreen())),
              const SizedBox(width: 10),
              _action('Send', Icons.arrow_upward,
                  () => _push(const SendMoneyScreen())),
              const SizedBox(width: 10),
              _action('Request', Icons.arrow_downward,
                  () => _push(const RequestMoneyScreen())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _requestsTab() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<Map<String, dynamic>>(
        future: _requests,
        emptyMessage: 'No money requests.',
        emptyIcon: Icons.request_quote_outlined,
        builder: (context, items) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _RequestTile(
            request: items[i],
            onChanged: _reload,
          ),
        ),
      ),
    );
  }

  Widget _transfersTab() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<Map<String, dynamic>>(
        future: _transfers,
        emptyMessage: 'No transfers yet.',
        emptyIcon: Icons.swap_horiz,
        builder: (context, items) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _TransferTile(
            transfer: items[i],
            onChanged: _reload,
          ),
        ),
      ),
    );
  }
}

/// A pending/recent transfer — accept/decline if incoming, reverse if mine
/// and still inside the reversal window.
class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.transfer, required this.onChanged});

  final Map<String, dynamic> transfer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final id = _pick(transfer, ['id', 'transfer_id', 'tid']);
    final amount = num.tryParse(_pick(transfer, ['amount'], '0')) ?? 0;
    final currency = _pick(transfer, ['currency'], 'USD');
    final status = _pick(transfer, ['status'], 'pending');
    final toUserId = _pick(transfer, ['to_user_id', 'recipient_id']);
    final incoming = currentUserId != null && toUserId == currentUserId;
    final who = _pick(transfer, [
      incoming ? 'from_name' : 'to_name',
      'counterparty_name',
      'user_name',
    ], 'Someone');
    final pending = status.toLowerCase() == 'pending';
    final reversible = !incoming &&
        (transfer['can_reverse'] == true || pending);
    final scheme = Theme.of(context).colorScheme;

    Future<void> act(Future<void> Function() op, String ok) async {
      try {
        await op();
        if (context.mounted) showInfo(context, ok);
        onChanged();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            (incoming ? const Color(0xFF22C55E) : scheme.primary)
                .withValues(alpha: 0.16),
        child: Icon(incoming ? Icons.south_west : Icons.north_east,
            color: incoming ? const Color(0xFF22C55E) : scheme.primary),
      ),
      title: Text(
          incoming ? 'From $who' : 'To $who',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${_money(amount, currency)} · $status'),
      trailing: incoming && pending
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Decline',
                  icon: Icon(Icons.close, color: scheme.error),
                  onPressed: () =>
                      act(() => api.wallet.declineTransfer(id), 'Declined'),
                ),
                FilledButton(
                  onPressed: () =>
                      act(() => api.wallet.acceptTransfer(id), 'Accepted'),
                  child: const Text('Accept'),
                ),
              ],
            )
          : reversible
              ? OutlinedButton(
                  onPressed: () => act(
                      () => api.wallet.reverseTransfer(id), 'Reversed'),
                  child: const Text('Reverse'),
                )
              : null,
    );
  }
}

/// A pending money request — pay/decline if it's owed by me, cancel if mine.
class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onChanged});

  final Map<String, dynamic> request;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final id = _pick(request, ['id', 'request_id']);
    final amount = num.tryParse(_pick(request, ['amount'], '0')) ?? 0;
    final currency = _pick(request, ['currency'], 'USD');
    final note = _pick(request, ['note', 'message']);
    final toUserId = _pick(request, ['to_user_id', 'payer_id']);
    // Incoming = I'm being asked to pay (I'm the payer/to_user).
    final incoming = currentUserId != null && toUserId == currentUserId;
    final who = _pick(request, [
      incoming ? 'from_name' : 'to_name',
      'requester_name',
      'counterparty_name',
      'user_name',
    ], 'Someone');
    final scheme = Theme.of(context).colorScheme;

    Future<void> act(Future<void> Function() op, String ok) async {
      try {
        await op();
        if (context.mounted) showInfo(context, ok);
        onChanged();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (incoming ? const Color(0xFFF59E0B) : scheme.primary)
            .withValues(alpha: 0.18),
        child: Icon(
            incoming ? Icons.call_received : Icons.call_made,
            color: incoming ? const Color(0xFFF59E0B) : scheme.primary),
      ),
      title: Text(incoming ? '$who requested from you' : 'You requested from $who',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(note.isEmpty
          ? _money(amount, currency)
          : '${_money(amount, currency)} · $note'),
      isThreeLine: false,
      trailing: incoming
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Decline',
                  icon: Icon(Icons.close, color: scheme.error),
                  onPressed: () =>
                      act(() => api.wallet.declineRequest(id), 'Declined'),
                ),
                FilledButton(
                  onPressed: () =>
                      act(() => api.wallet.payRequest(id), 'Paid $who'),
                  child: const Text('Pay'),
                ),
              ],
            )
          : OutlinedButton(
              onPressed: () =>
                  act(() => api.wallet.cancelRequest(id), 'Cancelled'),
              child: const Text('Cancel'),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(height: 10),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});

  final WalletTxn txn;

  @override
  Widget build(BuildContext context) {
    final incoming = txn.amount >= 0;
    final color =
        incoming ? const Color(0xFF22C55E) : Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(incoming ? Icons.south_west : Icons.north_east,
            size: 20, color: color),
      ),
      title: Text(txn.type ?? 'Transaction',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(txn.note ?? txn.counterpartyName ?? ''),
      trailing: Text(
        '${incoming ? '+' : '−'}${_money(txn.amount.abs(), txn.currency)}',
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}

/// Top up the wallet: enter an amount, start the provider intent and confirm.
class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});

  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  final _amount = TextEditingController();
  bool _busy = false;

  static const _presets = [10, 25, 50, 100, 250];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _topUp() async {
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      showInfo(context, 'Enter a valid amount.');
      return;
    }
    setState(() => _busy = true);
    try {
      final intent = await api.wallet.topupIntent(amount);
      // Best-effort confirm; demo backends auto-complete the intent.
      final id = intent['id'] ?? intent['intent_id'] ?? intent['topup_id'];
      if (id != null) {
        await api.wallet.confirmTopupIntent({'intent_id': '$id'});
      }
      if (mounted) {
        showInfo(context, 'Added ${_amount.text} to your wallet');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add money')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text('+$p'),
                    onPressed: () => setState(() => _amount.text = '$p'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _topUp,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_card),
              label: const Text('Add money'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Past wallet top-ups.
class TopUpHistoryScreen extends StatefulWidget {
  const TopUpHistoryScreen({super.key});

  @override
  State<TopUpHistoryScreen> createState() => _TopUpHistoryScreenState();
}

class _TopUpHistoryScreenState extends State<TopUpHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _topups;

  @override
  void initState() {
    super.initState();
    _topups = api.wallet.topups().then((d) => _mapList(d, 'topups'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top-up history')),
      body: MaxWidth(
        child: AsyncList<Map<String, dynamic>>(
          future: _topups,
          emptyMessage: 'No top-ups yet.',
          emptyIcon: Icons.add_card_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = items[i];
              final amount =
                  num.tryParse(_pick(t, ['amount'], '0')) ?? 0;
              final currency = _pick(t, ['currency'], 'USD');
              final status = _pick(t, ['status'], 'completed');
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: Text(_money(amount, currency)),
                subtitle: Text('Status: $status'),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Sets the money-transfer security question and answer.
class _SecurityDialog extends StatefulWidget {
  const _SecurityDialog();

  @override
  State<_SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<_SecurityDialog> {
  final _question = TextEditingController();
  final _answer = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_question.text.trim().isEmpty || _answer.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await api.wallet.setSecurity({
        'question': _question.text.trim(),
        'answer': _answer.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        showInfo(context, 'Security updated');
      }
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
      title: const Text('Transfer security'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'A question others must answer to send you money, and your answer.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _question,
            decoration: const InputDecoration(
                labelText: 'Security question', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            decoration: const InputDecoration(
                labelText: 'Answer', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Send money: search a recipient, then enter amount, note and the security
/// answer required by the transfer.
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key, this.recipient});

  /// Optional preselected recipient (e.g. from a scanned pay QR).
  final PublicUser? recipient;

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _answer = TextEditingController();

  Future<List<PublicUser>>? _results;
  late PublicUser? _recipient = widget.recipient;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _amount.dispose();
    _note.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = api.users.search(q));
  }

  Future<void> _send() async {
    final amount = num.tryParse(_amount.text.trim());
    if (_recipient == null || amount == null || amount <= 0) {
      showInfo(context, 'Pick a recipient and a valid amount.');
      return;
    }
    setState(() => _busy = true);
    try {
      await api.wallet.sendMoney(
        toUserId: _recipient!.userId,
        amount: amount,
        answer: _answer.text,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) {
        showInfo(context, 'Sent ${_amount.text} to ${_recipient!.name}');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send money')),
      body: MaxWidth(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_recipient == null) ...[
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Find recipient',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _runSearch),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_results != null)
              FutureBuilder<List<PublicUser>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final users = snapshot.data ?? const [];
                  if (users.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No matches.')));
                  }
                  return Column(
                    children: [
                      for (final u in users)
                        ListTile(
                          leading: Avatar(url: u.picture, name: u.name),
                          title: Text(u.name),
                          subtitle: u.username != null ? Text(u.handle) : null,
                          onTap: () => setState(() => _recipient = u),
                        ),
                    ],
                  );
                },
              ),
          ] else ...[
            Card(
              child: ListTile(
                leading: Avatar(
                    url: _recipient!.picture, name: _recipient!.name),
                title: Text(_recipient!.name),
                subtitle:
                    _recipient!.username != null ? Text(_recipient!.handle) : null,
                trailing: TextButton(
                  onPressed: () => setState(() => _recipient = null),
                  child: const Text('Change'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _answer,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Security answer',
                helperText: 'Required to authorize the transfer',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Send'),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Request money: search a recipient, then enter amount and an optional note.
class RequestMoneyScreen extends StatefulWidget {
  const RequestMoneyScreen({super.key});

  @override
  State<RequestMoneyScreen> createState() => _RequestMoneyScreenState();
}

class _RequestMoneyScreenState extends State<RequestMoneyScreen> {
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  Future<List<PublicUser>>? _results;
  PublicUser? _from;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = api.users.search(q));
  }

  Future<void> _request() async {
    final amount = num.tryParse(_amount.text.trim());
    if (_from == null || amount == null || amount <= 0) {
      showInfo(context, 'Pick someone and a valid amount.');
      return;
    }
    setState(() => _busy = true);
    try {
      await api.wallet.requestMoney(
        toUserId: _from!.userId,
        amount: amount,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) {
        showInfo(context, 'Requested ${_amount.text} from ${_from!.name}');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request money')),
      body: MaxWidth(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_from == null) ...[
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Request from',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _runSearch),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_results != null)
              FutureBuilder<List<PublicUser>>(
                future: _results,
                builder: (context, snapshot) {
                  final users = snapshot.data ?? const [];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (users.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No matches.')));
                  }
                  return Column(children: [
                    for (final u in users)
                      ListTile(
                        leading: Avatar(url: u.picture, name: u.name),
                        title: Text(u.name),
                        subtitle: u.username != null ? Text(u.handle) : null,
                        onTap: () => setState(() => _from = u),
                      ),
                  ]);
                },
              ),
          ] else ...[
            Card(
              child: ListTile(
                leading: Avatar(url: _from!.picture, name: _from!.name),
                title: Text(_from!.name),
                subtitle: _from!.username != null ? Text(_from!.handle) : null,
                trailing: TextButton(
                    onPressed: () => setState(() => _from = null),
                    child: const Text('Change')),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _request,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.request_page_outlined),
              label: const Text('Request'),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
