import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

String _money(num amount, String currency) =>
    '$currency ${amount.toStringAsFixed(2)}';

/// Wallet overview: balance, earnings and recent transactions, with an entry
/// point to send money.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<WalletSummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = api.wallet.summary();
  }

  Future<void> _reload() async {
    setState(() => _summary = api.wallet.summary());
    await _summary;
  }

  Future<void> _send() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const SendMoneyScreen(),
    ));
    if (sent == true) _reload();
  }

  Future<void> _request() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const RequestMoneyScreen(),
    ));
    if (done == true) _reload();
  }

  void _sendOrRequest() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Send money'),
              onTap: () {
                Navigator.pop(context);
                _send();
              },
            ),
            ListTile(
              leading: const Icon(Icons.request_page_outlined),
              title: const Text('Request money'),
              onTap: () {
                Navigator.pop(context);
                _request();
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
      appBar: AppBar(title: const Text('Wallet')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sendOrRequest,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Transfer'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
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
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Balance',
                          style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.8))),
                      const SizedBox(height: 8),
                      Text(_money(w.balance, w.currency),
                          style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 34,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _StatCard(
                            label: 'Earned',
                            value: _money(w.totalEarned, w.currency),
                            icon: Icons.trending_up)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _StatCard(
                            label: 'Spent',
                            value: _money(w.totalSpent, w.currency),
                            icon: Icons.trending_down)),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Recent activity',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (w.recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No transactions yet.')),
                  )
                else
                  ...w.recent.map((t) => _TxnTile(txn: t)),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.bold)),
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
    final color = incoming ? Colors.green : Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(incoming ? Icons.south_west : Icons.north_east, size: 18),
      ),
      title: Text(txn.type ?? 'Transaction'),
      subtitle: Text(txn.note ?? txn.counterpartyName ?? ''),
      trailing: Text(
        '${incoming ? '+' : ''}${_money(txn.amount, txn.currency)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Send money: search a recipient, then enter amount, note and the security
/// answer required by the transfer.
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({super.key});

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _answer = TextEditingController();

  Future<List<PublicUser>>? _results;
  PublicUser? _recipient;
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
      body: ListView(
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
      body: ListView(
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
    );
  }
}
