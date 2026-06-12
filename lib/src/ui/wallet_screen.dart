import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../okayspace_api.dart';
import 'cashout_screen.dart';
import 'common.dart';
import 'pay_qr_screen.dart';
import 'split_bill_screen.dart';
import 'wallet_insights_screen.dart';

String _money(num amount, String currency) =>
    '$currency ${amount.toStringAsFixed(2)}';

/// Venmo's signature blue, used for the primary payment actions.
const _venmoBlue = Color(0xFF008CFF);

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Venmo-style confirmation: big amount over the recipient's avatar with one
/// prominent blue button. Returns true when confirmed.
Future<bool> _confirmPayment(
  BuildContext context, {
  required PublicUser to,
  required num amount,
  required String currency,
  String? note,
  bool request = false,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(url: to.picture, name: to.name, radius: 30),
              const SizedBox(height: 10),
              Text(request ? 'Request from ${to.name}' : 'Pay ${to.name}',
                  style: TextStyle(color: scheme.outline, fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                  currency.isEmpty
                      ? amount.toStringAsFixed(2)
                      : _money(amount, currency),
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.bold)),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(note,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.outline)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: _venmoBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50)),
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(request ? 'Request' : 'Pay',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok == true;
}

/// Venmo-style full-screen success: a blue takeover with a check, the amount,
/// and who it went to (or was requested from).
class _PaymentDoneScreen extends StatelessWidget {
  const _PaymentDoneScreen({required this.headline, required this.detail});

  final String headline;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _venmoBlue,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.check, color: Colors.white, size: 52),
                ),
                const SizedBox(height: 24),
                Text(headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(detail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 16)),
                const SizedBox(height: 40),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      minimumSize: const Size(160, 48)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

/// Money requests/transfers come back as `{incoming: [...], outgoing: [...]}`.
/// Merge them into one list, tagging each with `_incoming` so the UI can show
/// the right actions regardless of payload field names.
List<Map<String, dynamic>> _moneyList(dynamic data) {
  if (data is Map && (data['incoming'] != null || data['outgoing'] != null)) {
    Map<String, dynamic> tag(dynamic e, bool incoming) =>
        {...Map<String, dynamic>.from(e as Map), '_incoming': incoming};
    final incoming = (data['incoming'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => tag(e, true));
    final outgoing = (data['outgoing'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => tag(e, false));
    return [...incoming, ...outgoing];
  }
  return _mapList(data);
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

  /// Masks amounts on the overview (privacy in public places).
  bool _hideBalance = false;

  /// Recent-activity direction filter: 'all' | 'in' | 'out'.
  String _txnFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summary = api.wallet.summary();
    _requests = api.wallet.moneyRequests().then(_moneyList);
    _transfers = api.wallet.transfers().then(_moneyList);
  }

  Future<void> _reload() async {
    setState(_load);
    await _summary;
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) _reload();
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

  /// Selected bottom-nav tab: Home / Requests / Transfers / Me.
  int _tab = 0;
  late final Future<User> _meUser = api.auth.me();

  /// A nav icon carrying a count badge of items matching [needsAction].
  Widget _badgedIcon(IconData icon,
      Future<List<Map<String, dynamic>>> future,
      bool Function(Map<String, dynamic>) needsAction) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        final count = (snapshot.data ?? const []).where(needsAction).length;
        if (count == 0) return Icon(icon);
        return Badge.count(count: count, child: Icon(icon));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
          title: Text(const ['Wallet', 'Requests', 'Transfers', 'Me'][_tab])),
      body: MaxWidth(
        child: switch (_tab) {
          1 => _requestsTab(),
          2 => _transfersTab(),
          3 => _meTab(),
          _ => _overview(),
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _venmoBlue,
        foregroundColor: Colors.white,
        onPressed: _payOrRequest,
        label: const Text('Pay or Request',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: _venmoBlue.withValues(alpha: 0.18),
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: _badgedIcon(Icons.request_quote_outlined, _requests,
                  (m) => m['_incoming'] == true),
              label: 'Requests'),
          NavigationDestination(
              icon: _badgedIcon(
                  Icons.swap_horiz,
                  _transfers,
                  (m) =>
                      m['_incoming'] == true &&
                      _pick(m, ['status'], 'pending').toLowerCase() ==
                          'pending'),
              label: 'Transfers'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Me'),
        ],
      ),
    );
  }

  /// Venmo-style Me tab: profile header with the pay QR shortcut, then the
  /// wallet's settings and tools (previously hidden in the overflow menu).
  Widget _meTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<User>(
          future: _meUser,
          builder: (context, snap) {
            final u = snap.data;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Avatar(url: u?.picture, name: u?.name ?? '?', radius: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u?.name ?? '…',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                        if (u != null)
                          Text(u.handle,
                              style: TextStyle(
                                  color: scheme.outline, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code, color: _venmoBlue),
                    tooltip: 'My pay QR',
                    onPressed: () => _push(const PayQrScreen()),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        for (final (icon, label, onTap) in <(IconData, String, VoidCallback)>[
          (Icons.qr_code, 'My pay QR', () => _push(const PayQrScreen())),
          (
            Icons.insights_outlined,
            'Insights',
            () => _push(const WalletInsightsScreen())
          ),
          (
            Icons.payments_outlined,
            'Cash out',
            () => _push(const CashOutScreen())
          ),
          (
            Icons.add_card_outlined,
            'Top-up history',
            () => _push(const TopUpHistoryScreen())
          ),
          (
            Icons.history,
            'Transfer history',
            () => _push(const TransferHistoryScreen())
          ),
          (Icons.currency_exchange, 'Change currency', _changeCurrency),
          (Icons.lock_outline, 'Transfer security', _security),
        ])
          ListTile(
            leading: Icon(icon, color: _venmoBlue),
            title: Text(label),
            trailing: Icon(Icons.chevron_right, color: scheme.outline),
            onTap: onTap,
          ),
      ],
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
          final txns = switch (_txnFilter) {
            'in' => w.recent.where((t) => t.amount >= 0).toList(),
            'out' => w.recent.where((t) => t.amount < 0).toList(),
            _ => w.recent,
          };
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _balanceCard(w, scheme),
              ..._quickSendRow(w),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _StatCard(
                          label: 'Earned',
                          value: _hideBalance
                              ? '••••'
                              : _money(w.totalEarned, w.currency),
                          icon: Icons.trending_up,
                          color: const Color(0xFF22C55E))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                          label: 'Spent',
                          value: _hideBalance
                              ? '••••'
                              : _money(w.totalSpent, w.currency),
                          icon: Icons.trending_down,
                          color: const Color(0xFFF43F5E))),
                ],
              ),
              const SizedBox(height: 16),
              _BudgetCard(summary: w, hideAmounts: _hideBalance),
              if (w.tipsTotal > 0 ||
                  w.subsTotal > 0 ||
                  w.adsTotal > 0 ||
                  w.activeSubscribers > 0) ...[
                const SizedBox(height: 16),
                _earningsCard(w, scheme),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Recent activity',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  for (final (id, label) in const [
                    ('all', 'All'),
                    ('in', 'In'),
                    ('out', 'Out')
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _txnFilter == id,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _txnFilter = id),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (txns.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                      child: Text(_txnFilter == 'all'
                          ? 'No transactions yet.'
                          : 'Nothing ${_txnFilter == 'in' ? 'incoming' : 'outgoing'} yet.')),
                )
              else
                // Venmo-style: transactions grouped under month headers.
                ...() {
                  final now = DateTime.now();
                  final widgets = <Widget>[];
                  String? lastKey;
                  for (final t in txns) {
                    final d = t.createdAt;
                    final key = d == null ? 'earlier' : '${d.year}-${d.month}';
                    if (key != lastKey) {
                      lastKey = key;
                      final label = d == null
                          ? 'Earlier'
                          : d.year == now.year && d.month == now.month
                              ? 'This month'
                              : '${_monthNames[d.month - 1]}'
                                  '${d.year == now.year ? '' : ' ${d.year}'}';
                      widgets.add(Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                        child: Text(label,
                            style: TextStyle(
                                color: scheme.outline,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.4)),
                      ));
                    }
                    widgets.add(_TxnTile(
                        txn: t, hideAmount: _hideBalance, onChanged: _reload));
                  }
                  return widgets;
                }(),
            ],
          );
        },
      ),
    );
  }

  /// Venmo-style balance header: flat bordered card, big amount, and
  /// Add money / Cash out side by side.
  Widget _balanceCard(WalletSummary w, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Wallet balance',
                    style: TextStyle(color: scheme.outline, fontSize: 13)),
              ),
              InkWell(
                onTap: () => setState(() => _hideBalance = !_hideBalance),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                      _hideBalance
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: scheme.outline,
                      size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_hideBalance ? '••••••' : _money(w.balance, w.currency),
              style:
                  const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: _venmoBlue,
                      foregroundColor: Colors.white),
                  onPressed: () => _push(const AddMoneyScreen()),
                  child: const Text('Add money'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _venmoBlue,
                      side: const BorderSide(color: _venmoBlue)),
                  onPressed: () => _push(const CashOutScreen()),
                  child: const Text('Cash out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The Venmo-signature primary action: one button for pay/request/split/QR.
  Future<void> _payOrRequest() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (id, icon, title, sub) in const [
              ('pay', Icons.arrow_upward, 'Pay', 'Send money to someone'),
              ('request', Icons.arrow_downward, 'Request',
                  'Ask someone to pay you'),
              ('split', Icons.call_split, 'Split a bill',
                  'Divide a total across friends'),
              ('qr', Icons.qr_code, 'Scan or show QR',
                  'Pay or get paid in person'),
            ])
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: _venmoBlue,
                  child: Icon(icon, color: Colors.white),
                ),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(sub),
                onTap: () => Navigator.pop(sheetContext, id),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'pay':
        await _push(const SendMoneyScreen());
      case 'request':
        await _push(const RequestMoneyScreen());
      case 'split':
        await _push(const SplitBillScreen());
      case 'qr':
        await _push(const PayQrScreen());
    }
  }

  /// People the user has sent money to recently (unique, newest first).
  List<({String id, String name})> _quickRecipients(WalletSummary w) {
    final seen = <String>{};
    final out = <({String id, String name})>[];
    for (final t in [...w.sent, ...w.recent.where((t) => t.amount < 0)]) {
      final id = t.counterpartyId;
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      out.add((id: id, name: t.counterpartyName ?? 'User'));
      if (out.length >= 10) break;
    }
    return out;
  }

  /// A horizontal strip of recent recipients for one-tap repeat sends.
  List<Widget> _quickSendRow(WalletSummary w) {
    final people = _quickRecipients(w);
    if (people.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text('Quick send',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: people.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final p = people[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _push(SendMoneyScreen(
                  recipient: PublicUser(userId: p.id, name: p.name))),
              child: SizedBox(
                width: 60,
                child: Column(
                  children: [
                    Avatar(name: p.name, radius: 24),
                    const SizedBox(height: 6),
                    Text(p.name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  /// Creator earnings split by source (tips / subscriptions / ads).
  Widget _earningsCard(WalletSummary w, ColorScheme scheme) {
    Widget row(IconData icon, Color color, String label, num amount) =>
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Text(_hideBalance ? '••••' : _money(amount, w.currency),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Earnings breakdown',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (w.activeSubscribers > 0)
                  Text(
                      '${w.activeSubscribers} subscriber${w.activeSubscribers == 1 ? '' : 's'}',
                      style: TextStyle(color: scheme.outline, fontSize: 12)),
              ],
            ),
            row(Icons.volunteer_activism_outlined, const Color(0xFFE11D48),
                'Tips', w.tipsTotal),
            row(Icons.workspace_premium_outlined, const Color(0xFF8B5CF6),
                'Subscriptions', w.subsTotal),
            row(Icons.campaign_outlined, const Color(0xFF0EA5E9), 'Ads',
                w.adsTotal),
          ],
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
    final incoming = transfer['_incoming'] as bool? ??
        (currentUserId != null && toUserId == currentUserId);
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
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () =>
                      act(() => api.wallet.acceptTransfer(id), 'Accepted'),
                  child: const Text('Accept'),
                ),
              ],
            )
          : reversible
              ? OutlinedButton(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
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
    final incoming = request['_incoming'] as bool? ??
        (currentUserId != null && toUserId == currentUserId);
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
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () =>
                      act(() => api.wallet.payRequest(id), 'Paid $who'),
                  child: const Text('Pay'),
                ),
              ],
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () =>
                  act(() => api.wallet.cancelRequest(id), 'Cancelled'),
              child: const Text('Cancel'),
            ),
    );
  }
}

/// A monthly spending budget, kept on-device. Spend-to-date is computed from
/// this month's outgoing transactions in the wallet summary.
class _BudgetCard extends StatefulWidget {
  const _BudgetCard({required this.summary, this.hideAmounts = false});

  final WalletSummary summary;
  final bool hideAmounts;

  @override
  State<_BudgetCard> createState() => _BudgetCardState();
}

class _BudgetCardState extends State<_BudgetCard> {
  static const _storageKey = 'okayspace.wallet_budget';
  static const _storage = FlutterSecureStorage();
  static const _presets = [50, 100, 200, 500, 1000];

  num? _budget;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _storage.read(key: _storageKey).then((v) {
      if (mounted) {
        setState(() {
          _budget = v == null ? null : num.tryParse(v);
          _loaded = true;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  Future<void> _save(num? budget) async {
    setState(() => _budget = budget);
    try {
      if (budget == null) {
        await _storage.delete(key: _storageKey);
      } else {
        await _storage.write(key: _storageKey, value: '$budget');
      }
    } catch (_) {/* best effort */}
  }

  num get _monthSpend {
    final now = DateTime.now();
    return widget.summary.recent
        .where((t) =>
            t.amount < 0 &&
            t.createdAt != null &&
            t.createdAt!.year == now.year &&
            t.createdAt!.month == now.month)
        .fold<num>(0, (a, t) => a + t.amount.abs());
  }

  Future<void> _edit() async {
    final picked = await showModalBottomSheet<num?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Monthly spending budget',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in _presets)
                    ChoiceChip(
                      label: Text('$p'),
                      selected: _budget == p,
                      onSelected: (_) => Navigator.pop(sheetContext, p),
                    ),
                  if (_budget != null)
                    ActionChip(
                      avatar: const Icon(Icons.close, size: 16),
                      label: const Text('Remove budget'),
                      onPressed: () => Navigator.pop(sheetContext, -1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _save(picked == -1 ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final w = widget.summary;
    final budget = _budget;

    if (budget == null || budget <= 0) {
      return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _edit,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.savings_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Set a monthly spending budget',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right, color: scheme.outline),
              ],
            ),
          ),
        ),
      );
    }

    final spent = _monthSpend;
    final frac = (spent / budget).clamp(0.0, 1.0);
    final over = spent > budget;
    final near = !over && spent >= budget * 0.8;
    final color = over
        ? scheme.error
        : near
            ? const Color(0xFFF59E0B)
            : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: over ? Border.all(color: scheme.error) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Monthly budget',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              InkWell(
                onTap: _edit,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.tune, size: 18, color: scheme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.hideAmounts
                ? '••••'
                : over
                    ? '${_money(spent, w.currency)} spent — '
                        '${_money(spent - budget, w.currency)} over budget'
                    : '${_money(spent, w.currency)} of '
                        '${_money(budget, w.currency)} spent this month',
            style: TextStyle(
                color: over ? scheme.error : scheme.outline, fontSize: 12),
          ),
        ],
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
  const _TxnTile({required this.txn, this.hideAmount = false, this.onChanged});

  final WalletTxn txn;
  final bool hideAmount;

  /// Called when a follow-up action (e.g. send again) changed the wallet.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final incoming = txn.amount >= 0;
    final color =
        incoming ? const Color(0xFF22C55E) : Theme.of(context).colorScheme.error;
    // Venmo-style: person-first title, note + relative time underneath.
    final who = txn.counterpartyName;
    final title = who != null
        ? (incoming ? '$who paid you' : 'You paid $who')
        : (txn.type ?? 'Transaction');
    final sub = [
      if (txn.note != null && txn.note!.isNotEmpty)
        txn.note!
      else if (who != null && txn.type != null)
        txn.type!,
      if (txn.createdAt != null) shortAgo(txn.createdAt!),
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onTap: () => _showDetails(context),
      leading: who != null
          ? Avatar(name: who, radius: 21)
          : Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(incoming ? Icons.south_west : Icons.north_east,
                  size: 20, color: color),
            ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: Text(
        hideAmount
            ? '••••'
            : '${incoming ? '+' : '−'} ${_money(txn.amount.abs(), txn.currency)}',
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) async {
    final incoming = txn.amount >= 0;
    final color = incoming
        ? const Color(0xFF22C55E)
        : Theme.of(context).colorScheme.error;
    final scheme = Theme.of(context).colorScheme;
    final canResend = !incoming && txn.counterpartyId != null;

    Widget detail(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(label,
                    style: TextStyle(color: scheme.outline, fontSize: 13)),
              ),
              Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                        incoming ? Icons.south_west : Icons.north_east,
                        size: 20,
                        color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(txn.type ?? 'Transaction',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Text(
                    '${incoming ? '+' : '−'}${_money(txn.amount.abs(), txn.currency)}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (txn.counterpartyName != null)
                detail(incoming ? 'From' : 'To', txn.counterpartyName!),
              if (txn.note != null && txn.note!.isNotEmpty)
                detail('Note', txn.note!),
              if (txn.createdAt != null)
                detail('Date',
                    '${txn.createdAt!.toLocal()}'.split('.').first),
              if (txn.id != null) detail('Reference', txn.id!),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (txn.id != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy reference'),
                      onPressed: () => Navigator.pop(sheetContext, 'copy'),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text('Share receipt'),
                    onPressed: () => Navigator.pop(sheetContext, 'receipt'),
                  ),
                  if (canResend)
                    FilledButton.icon(
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Send again'),
                      onPressed: () => Navigator.pop(sheetContext, 'resend'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'copy' && txn.id != null) {
      await Clipboard.setData(ClipboardData(text: txn.id!));
      if (context.mounted) showInfo(context, 'Reference copied');
    } else if (action == 'receipt') {
      final lines = [
        'OkaySpace receipt',
        '${txn.type ?? 'Transaction'}: '
            '${incoming ? '+' : '−'}${_money(txn.amount.abs(), txn.currency)}',
        if (txn.counterpartyName != null)
          '${incoming ? 'From' : 'To'}: ${txn.counterpartyName}',
        if (txn.note != null && txn.note!.isNotEmpty) 'Note: ${txn.note}',
        if (txn.createdAt != null)
          'Date: ${'${txn.createdAt!.toLocal()}'.split('.').first}',
        if (txn.id != null) 'Reference: ${txn.id}',
      ];
      await Clipboard.setData(ClipboardData(text: lines.join('\n')));
      if (context.mounted) showInfo(context, 'Receipt copied to share');
    } else if (action == 'resend' && canResend) {
      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SendMoneyScreen(
          recipient: PublicUser(
            userId: txn.counterpartyId!,
            name: txn.counterpartyName ?? 'User',
          ),
        ),
      ));
      if (changed == true) onChanged?.call();
    }
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
      appBar: const OkayAppBar(title: Text('Add money')),
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
    _load();
  }

  void _load() {
    _topups = api.wallet.topups().then((d) => _mapList(d, 'topups'));
  }

  Future<void> _cancel(String id) async {
    try {
      await api.wallet.cancelTopup(id);
      if (mounted) {
        showInfo(context, 'Top-up cancelled');
        setState(_load);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Top-up history')),
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
              final id = _pick(t, ['id', 'topup_id']);
              final amount =
                  num.tryParse(_pick(t, ['amount'], '0')) ?? 0;
              final currency = _pick(t, ['currency'], 'USD');
              final status = _pick(t, ['status'], 'completed');
              final pending = status.toLowerCase() == 'pending';
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.add)),
                title: Text(_money(amount, currency)),
                subtitle: Text('Status: $status'),
                trailing: pending && id.isNotEmpty
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36)),
                        onPressed: () => _cancel(id),
                        child: const Text('Cancel'),
                      )
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Read-only list of settled past transfers (`/money/transfers/history`).
class TransferHistoryScreen extends StatefulWidget {
  const TransferHistoryScreen({super.key});

  @override
  State<TransferHistoryScreen> createState() => _TransferHistoryScreenState();
}

class _TransferHistoryScreenState extends State<TransferHistoryScreen> {
  late final Future<List<Map<String, dynamic>>> _history =
      api.wallet.transferHistory().then(_moneyList);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Transfer history')),
      body: MaxWidth(
        child: AsyncList<Map<String, dynamic>>(
          future: _history,
          emptyMessage: 'No past transfers.',
          emptyIcon: Icons.history,
          builder: (context, items) => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = items[i];
              final amount = num.tryParse(_pick(t, ['amount'], '0')) ?? 0;
              final currency = _pick(t, ['currency'], 'USD');
              final status = _pick(t, ['status'], 'completed');
              final toUserId = _pick(t, ['to_user_id', 'recipient_id']);
              final incoming = t['_incoming'] as bool? ??
                  (currentUserId != null && toUserId == currentUserId);
              final who = _pick(t, [
                incoming ? 'from_name' : 'to_name',
                'counterparty_name',
                'user_name',
              ], 'Someone');
              final when = _pick(t, ['created_at', 'completed_at']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      (incoming ? const Color(0xFF22C55E) : scheme.primary)
                          .withValues(alpha: 0.16),
                  child: Icon(
                      incoming ? Icons.south_west : Icons.north_east,
                      color: incoming
                          ? const Color(0xFF22C55E)
                          : scheme.primary),
                ),
                title: Text(incoming ? 'From $who' : 'To $who',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  _money(amount, currency),
                  status,
                  if (when.isNotEmpty) when.split('T').first,
                ].join(' · ')),
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
  const SendMoneyScreen(
      {super.key, this.recipient, this.initialAmount, this.initialNote});

  /// Optional preselected recipient (e.g. from a scanned pay QR).
  final PublicUser? recipient;

  /// Optional amount/note prefill (e.g. embedded in a pay QR).
  final String? initialAmount;
  final String? initialNote;

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _search = TextEditingController();
  late final _amount = TextEditingController(text: widget.initialAmount);
  late final _note = TextEditingController(text: widget.initialNote);
  final _answer = TextEditingController();

  Future<List<PublicUser>>? _results;
  late PublicUser? _recipient = widget.recipient;
  bool _busy = false;

  /// Available balance, fetched for the overdraft hint (null while loading).
  num? _balance;
  String _currency = 'USD';

  static const _presets = [5, 10, 20, 50, 100];

  @override
  void initState() {
    super.initState();
    api.wallet.summary().then((w) {
      if (mounted) {
        setState(() {
          _balance = w.balance;
          _currency = w.currency;
        });
      }
    }).catchError((_) {});
  }

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

  bool get _overBalance {
    final amount = num.tryParse(_amount.text.trim());
    return _balance != null && amount != null && amount > _balance!;
  }

  /// Applies a keypad tap to the amount (digits, one '.', '<' = backspace,
  /// max two decimal places).
  void _tapKey(String k) {
    var t = _amount.text;
    if (k == '<') {
      if (t.isNotEmpty) t = t.substring(0, t.length - 1);
    } else if (k == '.') {
      if (t.contains('.')) return;
      t = t.isEmpty ? '0.' : '$t.';
    } else {
      if (t.contains('.') && t.split('.')[1].length >= 2) return;
      if (t == '0') t = '';
      t += k;
    }
    setState(() => _amount.text = t);
  }

  /// Venmo-style 3×4 numeric keypad.
  Widget _keypad() {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['.', '0', '<'],
        ])
          Row(
            children: [
              for (final k in row)
                Expanded(
                  child: InkWell(
                    onTap: () => _tapKey(k),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 52,
                      child: Center(
                        child: k == '<'
                            ? const Icon(Icons.backspace_outlined, size: 22)
                            : Text(k,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _send() async {
    final amount = num.tryParse(_amount.text.trim());
    if (_recipient == null || amount == null || amount <= 0) {
      showInfo(context, 'Pick a recipient and a valid amount.');
      return;
    }
    if (_overBalance) {
      showInfo(context, 'That\'s more than your available balance.');
      return;
    }
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final confirmed = await _confirmPayment(context,
        to: _recipient!, amount: amount, currency: _currency, note: note);
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.wallet.sendMoney(
        toUserId: _recipient!.userId,
        amount: amount,
        answer: _answer.text,
        note: note,
      );
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _PaymentDoneScreen(
            headline: 'You paid ${_recipient!.name}',
            detail: [
              _money(amount, _currency),
              if (note != null) note,
            ].join(' · '),
          ),
        ));
        if (mounted) Navigator.of(context).pop(true);
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
      appBar: const OkayAppBar(title: Text('Send money')),
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
            // Venmo-style amount entry: big centered display over a keypad.
            Text(
              '$_currency ${_amount.text.isEmpty ? '0' : _amount.text}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: _overBalance
                      ? Theme.of(context).colorScheme.error
                      : null),
            ),
            const SizedBox(height: 2),
            Text(
              _overBalance
                  ? 'More than your available balance'
                  : _balance != null
                      ? 'Available: ${_money(_balance!, _currency)}'
                      : '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: _overBalance
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 8),
            _keypad(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in _presets)
                  ActionChip(
                    label: Text('$p'),
                    onPressed: () => setState(() => _amount.text = '$p'),
                  ),
                if (_balance != null && _balance! > 0)
                  ActionChip(
                    label: const Text('Max'),
                    onPressed: () => setState(
                        () => _amount.text = _balance!.toStringAsFixed(2)),
                  ),
              ],
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
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final confirmed = await _confirmPayment(context,
        to: _from!, amount: amount, currency: '', note: note, request: true);
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.wallet.requestMoney(
        toUserId: _from!.userId,
        amount: amount,
        note: note,
      );
      if (mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _PaymentDoneScreen(
            headline: 'Request sent',
            detail: [
              'You requested ${amount.toStringAsFixed(2)} from ${_from!.name}',
              if (note != null) note,
            ].join(' · '),
          ),
        ));
        if (mounted) Navigator.of(context).pop(true);
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
      appBar: const OkayAppBar(title: Text('Request money')),
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in const [5, 10, 20, 50, 100])
                  ActionChip(
                    label: Text('$p'),
                    onPressed: () => setState(() => _amount.text = '$p'),
                  ),
              ],
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
