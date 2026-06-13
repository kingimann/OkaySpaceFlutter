import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../okayspace_api.dart';
import '../core/stripe_elements.dart';
import '../core/stripe_pay.dart';
import 'cashout_screen.dart';
import 'common.dart';
import 'pay_qr_screen.dart';
import 'spending_limits.dart';
import 'split_bill_screen.dart';
import 'tap_to_pay_screen.dart';
import 'wallet_insights_screen.dart';
import 'wallet_lock.dart';

String _money(num amount, String currency) => formatMoney(amount, currency);

/// Venmo's signature blue, used for the primary payment actions.
const _venmoBlue = Color(0xFF008CFF);

/// A Stripe Payment Link (dashboard-created, customer-chooses-amount) used
/// for wallet top-ups. When set, Add money goes straight to Stripe with no
/// backend involvement in the payment path; the webhook credits the wallet
/// via client_reference_id. Set with --dart-define=STRIPE_TOPUP_LINK=...
const _stripeTopupLink = String.fromEnvironment('STRIPE_TOPUP_LINK');

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Sort comparator: newest first, undated transactions last.
int _byNewest(WalletTxn a, WalletTxn b) {
  final ad = a.createdAt, bd = b.createdAt;
  if (ad == null && bd == null) return 0;
  if (ad == null) return 1;
  if (bd == null) return -1;
  return bd.compareTo(ad);
}

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
  const WalletScreen({super.key, this.embedded = false});

  /// True when hosted inside the home shell, whose floating bottom nav pill
  /// overlays the body — the FAB is lifted above it.
  final bool embedded;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with WidgetsBindingObserver {
  late Future<WalletSummary> _summary;
  late Future<List<Map<String, dynamic>>> _requests;
  late Future<List<Map<String, dynamic>>> _transfers;

  /// Masks amounts on the overview (privacy in public places).
  bool _hideBalance = false;

  /// True while the wallet PIN lock is engaged (set on open, cleared on a
  /// successful unlock).
  bool _pinLocked = false;

  /// Recent-activity direction filter: 'all' | 'in' | 'out'.
  String _txnFilter = 'all';

  /// Free-text transaction search; non-null while the search field is open.
  final _txnSearch = TextEditingController();
  bool _searching = false;

  /// Pinned quick-send favorites (persisted on-device), shown first.
  static const _favoritesKey = 'okayspace.wallet_favorites';
  static const _favStorage = FlutterSecureStorage();
  List<({String id, String name})> _favorites = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadFavorites();
    walletLock.enabled.then((enabled) {
      if (mounted && enabled && !walletLock.unlocked) {
        setState(() => _pinLocked = true);
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  /// Re-engage the PIN lock whenever the app leaves the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    walletLock.enabled.then((enabled) {
      if (enabled && mounted) {
        walletLock.relock();
        setState(() => _pinLocked = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _txnSearch.dispose();
    super.dispose();
  }

  // Pending counts for the tab badges, kept across refreshes so the badges
  // don't blink to zero while the lists reload. The generation token keeps
  // an out-of-order older fetch from overwriting a newer count.
  int _pendingRequests = 0;
  int _pendingTransfers = 0;
  int _loadGen = 0;

  void _load() {
    final gen = ++_loadGen;
    // Reconcile pending Stripe top-ups (Payment Link / checkout payments
    // finished outside the app) before showing the balance; best effort.
    _summary = api.wallet
        .topupSync()
        .catchError((_) {})
        .then((_) => api.wallet.summary())
        .then((w) async {
      // The summary may no longer carry transactions (they live on
      // /wallet/activity); fall back so the overview list isn't empty.
      // `recent` is what the overview renders — `sent` alone isn't enough.
      if (w.recent.isNotEmpty) return w;
      try {
        final raw = await api.wallet.activity();
        final txns = _mapList(raw, 'activity').map(WalletTxn.fromJson).toList()
          ..sort(_byNewest);
        if (txns.isEmpty) return w;
        return WalletSummary(
          currency: w.currency,
          balance: w.balance,
          totalEarned: w.totalEarned,
          totalSpent: w.totalSpent,
          tipsTotal: w.tipsTotal,
          subsTotal: w.subsTotal,
          adsTotal: w.adsTotal,
          activeSubscribers: w.activeSubscribers,
          subPrice: w.subPrice,
          recent: txns,
          sent: w.sent,
          raw: w.raw,
        );
      } catch (_) {
        return w;
      }
    });
    _requests = api.wallet.moneyRequests().then(_moneyList);
    _transfers = api.wallet.transfers().then(_moneyList);
    () async {
      try {
        final items = await _requests;
        if (mounted && gen == _loadGen) {
          setState(() => _pendingRequests =
              items.where((m) => m['_incoming'] == true).length);
        }
      } catch (_) {}
    }();
    () async {
      try {
        final items = await _transfers;
        if (mounted && gen == _loadGen) {
          setState(() => _pendingTransfers = items
              .where((m) =>
                  m['_incoming'] == true &&
                  _pick(m, ['status']).toLowerCase() == 'pending')
              .length);
        }
      } catch (_) {}
    }();
  }

  /// Set once the user edits favorites, so a late storage read can't clobber
  /// their change.
  bool _favsTouched = false;

  Future<void> _loadFavorites() async {
    try {
      final raw = await _favStorage.read(key: _favoritesKey);
      if (raw == null || !mounted || _favsTouched) return;
      final list = jsonDecode(raw);
      if (list is List) {
        setState(() {
          _favorites = [
            for (final e in list)
              if (e is Map && e['id'] is String)
                (id: e['id'] as String, name: '${e['name'] ?? 'User'}'),
          ];
        });
      }
    } catch (_) {/* start fresh */}
  }

  bool _isFavorite(String id) => _favorites.any((f) => f.id == id);

  Future<void> _toggleFavorite(({String id, String name}) person) async {
    _favsTouched = true;
    setState(() {
      _favorites = _isFavorite(person.id)
          ? _favorites.where((f) => f.id != person.id).toList()
          : [..._favorites, person];
    });
    try {
      await _favStorage.write(
        key: _favoritesKey,
        value: jsonEncode(
            [for (final f in _favorites) {'id': f.id, 'name': f.name}]),
      );
    } catch (_) {/* best effort */}
    if (mounted) {
      showInfo(context,
          _isFavorite(person.id) ? 'Pinned to quick send' : 'Unpinned');
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(_load);
    // Hold the refresh indicator until all three fetches settle; the
    // FutureBuilders surface their own errors, so swallow them here.
    await Future.wait<void>([
      _summary.then<void>((_) {}).catchError((_) {}),
      _requests.then<void>((_) {}).catchError((_) {}),
      _transfers.then<void>((_) {}).catchError((_) {}),
    ]);
  }

  Future<void> _push(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) _reload();
  }

  Future<void> _changeCurrency() async {
    // Fall back to USD if the summary hasn't loaded; the sheet still works.
    var current = 'USD';
    try {
      current = (await _summary).currency;
    } catch (_) {}
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Display currency',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final c in const ['USD', 'CAD', 'EUR', 'GBP', 'NGN', 'INR'])
              ListTile(
                title: Text(c),
                trailing: c == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
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

  /// A tab whose label carries a count badge when [count] is non-zero.
  Widget _countedTab(String label, int count) {
    return Tab(
      child: count == 0
          ? Text(label)
          : Badge.count(
              count: count,
              offset: const Offset(14, -4),
              child: Text(label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Another WalletScreen instance (home-shell tab vs pushed route) may have
    // unlocked already — honor the shared lock state.
    if (_pinLocked && walletLock.unlocked) _pinLocked = false;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: OkayAppBar(
          title: const Text('Wallet'),
          // While PIN-locked, the QR and tools must be gated too — they
          // expose balances, history, and pay actions.
          actions: _pinLocked
              ? const []
              : [
            IconButton(
              icon: const Icon(Icons.qr_code),
              tooltip: 'Pay by QR',
              onPressed: () => _push(const PayQrScreen()),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'cashout') _push(const CashOutScreen());
                if (v == 'currency') _changeCurrency();
                if (v == 'security') _security();
                if (v == 'topups') _push(const TopUpHistoryScreen());
                if (v == 'insights') _push(const WalletInsightsScreen());
                if (v == 'history') _push(const TransferHistoryScreen());
                if (v == 'lock') _walletLockSettings();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'insights', child: Text('Insights')),
                PopupMenuItem(value: 'cashout', child: Text('Cash out')),
                PopupMenuItem(value: 'currency', child: Text('Change currency')),
                PopupMenuItem(value: 'security', child: Text('Transfer security')),
                PopupMenuItem(value: 'topups', child: Text('Top-up history')),
                PopupMenuItem(
                    value: 'history', child: Text('Transfer history')),
                PopupMenuItem(value: 'lock', child: Text('Wallet lock')),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Overview'),
              _countedTab('Requests', _pendingRequests),
              _countedTab('Transfers', _pendingTransfers),
            ],
          ),
        ),
        body: MaxWidth(
          child: _pinLocked
              ? _lockGate()
              : TabBarView(
                  children: [_overview(), _requestsTab(), _transfersTab()],
                ),
        ),
        floatingActionButton: _pinLocked
            ? null
            : Padding(
          // Clear the home shell's floating nav pill when embedded.
          padding: EdgeInsets.only(bottom: widget.embedded ? 76 : 0),
          child: FloatingActionButton.extended(
            backgroundColor: _venmoBlue,
            foregroundColor: Colors.white,
            onPressed: _payOrRequest,
            label: const Text('Pay or Request',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  /// Shown instead of the wallet while the PIN lock is engaged.
  Widget _lockGate() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 56, color: scheme.primary),
          const SizedBox(height: 14),
          const Text('Wallet locked',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 6),
          Text('Enter your PIN to see balances and pay',
              style: TextStyle(color: scheme.outline, fontSize: 13)),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Icons.pin_outlined),
            label: const Text('Unlock'),
            onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const WalletPinScreen()));
              if (ok == true && mounted) setState(() => _pinLocked = false);
            },
          ),
        ],
      ),
    );
  }

  /// Set up, change, or remove the wallet PIN (current PIN required to
  /// change or remove).
  Future<void> _walletLockSettings() async {
    final enabled = await walletLock.enabled;
    if (!mounted) return;
    if (!enabled) {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => const WalletPinScreen(setup: true)));
      if (ok == true && mounted) setState(() => _pinLocked = false);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Change PIN'),
              onTap: () => Navigator.pop(sheetContext, 'change'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('Remove wallet lock'),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    // Verify the current PIN before any change.
    final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const WalletPinScreen()));
    if (verified != true || !mounted) return;
    if (choice == 'change') {
      await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => const WalletPinScreen(setup: true)));
    } else {
      await walletLock.clear();
      if (mounted) {
        showInfo(context, 'Wallet lock removed');
        setState(() => _pinLocked = false);
      }
    }
  }

  Widget _overview() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<WalletSummary>(
        future: _summary,
        builder: (context, snapshot) {
          // Skeleton only on first load; refreshes keep the data on screen.
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return _skeleton(Theme.of(context).colorScheme);
          }
          if (snapshot.hasError) {
            return CenteredMessage(
                message: messageFor(snapshot.error),
                icon: Icons.error_outline,
                onRetry: _reload);
          }
          final w = snapshot.data!;
          final scheme = Theme.of(context).colorScheme;
          final query = _searching ? _txnSearch.text.trim().toLowerCase() : '';
          bool matches(WalletTxn t) =>
              query.isEmpty ||
              [t.counterpartyName, t.note, t.type]
                  .any((s) => s != null && s.toLowerCase().contains(query));
          // Sorted defensively: month grouping relies on newest-first order.
          final txns = switch (_txnFilter) {
            'in' => w.recent.where((t) => t.amount >= 0 && matches(t)).toList(),
            'out' => w.recent.where((t) => t.amount < 0 && matches(t)).toList(),
            _ => w.recent.where(matches).toList(),
          }
            ..sort(_byNewest);
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
              SpendingLimitsCard(
                  txns: w.recent,
                  currency: w.currency,
                  hideAmounts: _hideBalance),
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
                    child: Row(
                      children: [
                        Text('Recent activity',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        TextButton(
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          onPressed: () =>
                              _push(const WalletActivityScreen()),
                          child: const Text('See all'),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(_searching ? Icons.search_off : Icons.search,
                        size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: _searching ? 'Close search' : 'Search activity',
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _txnSearch.clear();
                    }),
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
              if (_searching)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _txnSearch,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by name, note, or type',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              if (txns.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                      child: Text(query.isNotEmpty
                          ? 'No matches for "${_txnSearch.text.trim()}".'
                          : _txnFilter == 'all'
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

  /// Placeholder layout shown while the summary loads, shaped like the
  /// overview (balance card, stat row, transaction rows).
  Widget _skeleton(ColorScheme scheme) {
    Widget box(double height, {double? width, double radius = 12}) =>
        Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        box(150, radius: 16),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: box(92, radius: 16)),
            const SizedBox(width: 12),
            Expanded(child: box(92, radius: 16)),
          ],
        ),
        const SizedBox(height: 24),
        box(16, width: 140, radius: 6),
        const SizedBox(height: 16),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                box(42, width: 42, radius: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(13, width: 150, radius: 5),
                      const SizedBox(height: 6),
                      box(11, width: 90, radius: 5),
                    ],
                  ),
                ),
                box(14, width: 64, radius: 5),
              ],
            ),
          ),
      ],
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
            for (final (id, icon, title, sub) in [
              ('pay', Icons.arrow_upward, 'Pay', 'Send money to someone'),
              ('request', Icons.arrow_downward, 'Request',
                  'Ask someone to pay you'),
              ('split', Icons.call_split, 'Split a bill',
                  'Divide a total across friends'),
              ('qr', Icons.qr_code, 'Scan or show QR',
                  'Pay or get paid in person'),
              // NFC only exists on the mobile builds.
              if (!kIsWeb)
                ('nfc', Icons.contactless, 'Tap to pay',
                    'Hold your phone to a pay tag'),
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
      case 'nfc':
        await _push(const TapToPayScreen());
    }
  }

  /// Quick-send people: pinned favorites first, then recent recipients
  /// (unique, newest first).
  List<({String id, String name})> _quickRecipients(WalletSummary w) {
    final seen = <String>{for (final f in _favorites) f.id};
    final out = [..._favorites];
    for (final t in [...w.sent, ...w.recent.where((t) => t.amount < 0)]) {
      final id = t.counterpartyId;
      if (id == null || id.isEmpty || id == currentUserId || !seen.add(id)) {
        continue;
      }
      out.add((id: id, name: t.counterpartyName ?? 'User'));
      if (out.length >= 12) break;
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
            final pinned = _isFavorite(p.id);
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _push(SendMoneyScreen(
                  recipient: PublicUser(userId: p.id, name: p.name))),
              // Long-press pins/unpins the person to the front of the row.
              onLongPress: () => _toggleFavorite(p),
              child: SizedBox(
                width: 60,
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Avatar(name: p.name, radius: 24),
                        if (pinned)
                          const Positioned(
                            right: -2,
                            bottom: -2,
                            child: CircleAvatar(
                              radius: 9,
                              backgroundColor: Color(0xFFF59E0B),
                              child:
                                  Icon(Icons.star, size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
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
    // Missing status must read as non-actionable, not pending.
    final status = _pick(transfer, ['status']);
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
        if (!context.mounted) return;
        showInfo(context, ok);
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
      subtitle: Text([
        _money(amount, currency),
        if (status.isNotEmpty) status,
      ].join(' · ')),
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
        if (!context.mounted) return;
        showInfo(context, ok);
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
                  onPressed: () async {
                    // Self-imposed spending limits cover request payments
                    // too, not just direct sends — warn-and-override, same
                    // as SendMoney. Limits are advisory: a failed summary
                    // read must not block the payment.
                    if (spendingLimits.any) {
                      var txns = const <WalletTxn>[];
                      try {
                        final w = await api.wallet.summary();
                        txns = [...w.recent, ...w.sent];
                      } catch (_) {}
                      final exceeded =
                          spendingLimits.wouldExceed(txns, amount);
                      if (exceeded != null) {
                        if (!context.mounted) return;
                        final go = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Spending limit reached'),
                            content: Text(
                                'Paying this request takes '
                                '${exceeded.label.toLowerCase()}\'s spending '
                                'to ${_money(exceeded.spent + amount, currency)} '
                                'of your ${_money(exceeded.limit, currency)} '
                                'limit. Pay anyway?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  child: const Text('Pay anyway')),
                            ],
                          ),
                        );
                        if (go != true || !context.mounted) return;
                      }
                    }
                    if (!context.mounted) return;
                    // The transfer may require a security answer. A blank
                    // answer is a valid choice (no question set), so this
                    // dialog distinguishes Pay-with-blank from Cancel.
                    final controller = TextEditingController();
                    final String? answer;
                    try {
                      answer = await showDialog<String>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Security answer'),
                          content: TextField(
                            controller: controller,
                            autofocus: true,
                            obscureText: true,
                            decoration: const InputDecoration(
                                hintText:
                                    'Leave blank if you haven\'t set one',
                                border: OutlineInputBorder()),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(
                                    dialogContext, controller.text.trim()),
                                child: const Text('Pay')),
                          ],
                        ),
                      );
                    } finally {
                      controller.dispose();
                    }
                    if (answer == null || !context.mounted) return;
                    final a = answer;
                    await act(
                        () => api.wallet
                            .payRequest(id, answer: a.isEmpty ? null : a),
                        'Paid $who');
                  },
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

  /// Chip color per normalized status (Approved/Pending/Canceled/...).
  static Color _statusColor(BuildContext context, String status) =>
      switch (status) {
        'Approved' => const Color(0xFF22C55E),
        'Pending' => const Color(0xFFF59E0B),
        'Canceled' => Theme.of(context).colorScheme.outline,
        _ => Theme.of(context).colorScheme.error, // Failed / Reversed
      };

  @override
  Widget build(BuildContext context) {
    final incoming = txn.amount >= 0;
    final settled = txn.isSettled;
    final status = txn.statusLabel;
    final statusColor = _statusColor(context, status);
    // Canceled/failed money didn't move — mute it instead of coloring it
    // like real money.
    final color = !settled && status != 'Pending'
        ? Theme.of(context).colorScheme.outline
        : incoming
            ? const Color(0xFF22C55E)
            : Theme.of(context).colorScheme.error;
    // Venmo-style: person-first title, note + relative time underneath.
    // The backend's activity feed sends ready-made title/subtitle; fall
    // back to building one (older payloads said just "Transaction").
    final who = txn.counterpartyName;
    final title = txn.title ??
        (who != null
            ? (incoming ? '$who paid you' : 'You paid $who')
            : (txn.type ?? 'Transaction'));
    final sub = [
      if (txn.subtitle != null && txn.subtitle!.isNotEmpty)
        txn.subtitle!
      else if (txn.note != null && txn.note!.isNotEmpty)
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
              child: Icon(
                  status == 'Pending'
                      ? Icons.hourglass_top
                      : status == 'Canceled'
                          ? Icons.close
                          : incoming
                              ? Icons.south_west
                              : Icons.north_east,
                  size: 20,
                  color: color),
            ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            hideAmount
                ? '••••'
                : '${incoming ? '+' : '−'} ${_money(txn.amount.abs(), txn.currency)}',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                decoration: status == 'Canceled' || status == 'Failed'
                    ? TextDecoration.lineThrough
                    : null),
          ),
          Text(status,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Finds this transaction's top-up record on /wallet/topups: the activity
  /// feed has its own row ids, so cancel/resume must use the top-up's own
  /// id (and its client_secret). Matches by id first, then by
  /// pending-status + amount.
  Future<Map<String, dynamic>?> _findTopup() async {
    try {
      final raw = await api.wallet.topups();
      final list = raw is Map
          ? (raw['data'] ?? raw['topups'] ?? raw['items'] ?? raw['activity'])
          : raw;
      if (list is! List) return null;
      final maps = [
        for (final t in list.whereType<Map>()) t.cast<String, dynamic>(),
      ];
      for (final t in maps) {
        if (txn.id != null &&
            ('${t['id'] ?? ''}' == txn.id ||
                '${t['intent_id'] ?? ''}' == txn.id ||
                '${t['activity_id'] ?? ''}' == txn.id)) {
          return t;
        }
      }
      for (final t in maps) {
        final s = '${t['status'] ?? ''}'.toLowerCase();
        final pending = s.contains('pend') ||
            s.contains('requir') ||
            s.contains('process') ||
            s == 'created' ||
            s == 'open';
        if (!pending) continue;
        final amt = t['amount'];
        if (amt is num && (amt - txn.amount.abs()).abs() < 0.005) return t;
      }
    } catch (_) {/* fall through to the activity id */}
    return null;
  }

  Future<void> _cancelPending(BuildContext context) async {
    try {
      final t = await _findTopup();
      final tid = '${t?['id'] ?? txn.id ?? ''}';
      if (tid.isEmpty) throw StateError('No top-up id');
      await api.wallet.cancelTopup(tid);
      if (context.mounted) {
        showInfo(context, 'Transaction cancelled');
        onChanged?.call();
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// Resumes an unpaid (pending) top-up: reopen the in-app card form
  /// against the intent's existing client secret.
  Future<void> _resumePending(BuildContext context) async {
    var secret = '${txn.raw['client_secret'] ?? txn.raw['payment_client_secret'] ?? txn.raw['stripe_client_secret'] ?? ''}';
    if (secret.isEmpty) {
      // The activity row rarely carries the secret; the top-up record does.
      final t = await _findTopup();
      secret = '${t?['client_secret'] ?? t?['payment_client_secret'] ?? ''}';
    }
    if (!stripeElementsSupported || secret.isEmpty) {
      if (context.mounted) {
        showInfo(context,
            'This top-up can\'t be resumed here — start a new one from '
            'Add money (the pending one can be cancelled).');
      }
      return;
    }
    try {
      final cfg = await api.payments.config();
      final pk = '${cfg['publishable_key'] ?? ''}';
      if (pk.isEmpty || !context.mounted) return;
      final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _InlineCardPayScreen(
            publishableKey: pk,
            clientSecret: secret,
            amount: txn.amount.abs()),
      ));
      if (paid == true) {
        try {
          await api.wallet.confirmTopupIntent(
              {'intent_id': secret.split('_secret').first});
        } catch (_) {/* topup/sync reconciles */}
        if (context.mounted) {
          showInfo(context, 'Payment complete');
          onChanged?.call();
        }
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _showDetails(BuildContext context) async {
    final incoming = txn.amount >= 0;
    final color = incoming
        ? const Color(0xFF22C55E)
        : Theme.of(context).colorScheme.error;
    final scheme = Theme.of(context).colorScheme;
    final canResend = !incoming &&
        txn.counterpartyId != null &&
        txn.counterpartyId != currentUserId;

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
                    child: Text(txn.title ?? txn.type ?? 'Transaction',
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
              detail('Status', txn.statusLabel),
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
                  // Pending top-ups can be finished (resume the card
                  // payment) or cancelled outright.
                  if (txn.statusLabel == 'Pending' && incoming) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Resume payment'),
                      onPressed: () => Navigator.pop(sheetContext, 'resume'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel transaction'),
                      onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                    ),
                  ],
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
    if (action == 'cancel') {
      await _cancelPending(context);
    } else if (action == 'resume') {
      await _resumePending(context);
    } else if (action == 'copy' && txn.id != null) {
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
    if (amount == null || !amount.isFinite || amount <= 0) {
      showInfo(context, 'Enter a valid amount.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Native apps: the full Stripe PaymentSheet — card entry inside the
      // app against a server-created PaymentIntent.
      if (stripeSheetSupported) {
        final paid = await _paySheetTopUp(amount);
        if (paid != null) {
          if (paid && mounted) {
            showInfo(context,
                'Payment complete — your balance updates in a moment.');
            Navigator.of(context).pop(true);
          }
          return; // paid or user-cancelled; either way we're done
        }
        // null = sheet unavailable (no client secret) → hosted fallbacks.
      }
      // Web: the inline Payment Element — card entry embedded in the app,
      // no redirect to stripe.com. The hosted page is never opened
      // automatically: if the inline flow can't start, the user is told
      // why and chooses whether to use Stripe's page instead.
      if (stripeElementsSupported) {
        final result = await _inlineWebTopUp(amount);
        if (result.paid != null) {
          if (result.paid! && mounted) {
            showInfo(context,
                'Payment complete — your balance updates in a moment.');
            Navigator.of(context).pop(true);
          }
          return; // paid or user-cancelled
        }
        if (!mounted) return;
        final useHosted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Card form unavailable'),
            content: Text(
                '${result.failure ?? 'The in-app card form couldn\'t start.'}\n\n'
                'You can finish on Stripe\'s secure checkout page instead.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Use Stripe page')),
            ],
          ),
        );
        if (useHosted != true || !mounted) return;
        // Fall through to the hosted paths below — explicit user choice.
      }
      // Hosted fallback: a dashboard-created Stripe Payment Link — pure
      // Stripe, no backend call to start the payment. client_reference_id
      // ties the payment to this user for the crediting webhook.
      if (_stripeTopupLink.isNotEmpty && currentUserId == null) {
        // The cached id loads best-effort at startup; retry before silently
        // skipping the preferred Stripe link path.
        await loadCurrentUserId();
      }
      if (_stripeTopupLink.isNotEmpty && currentUserId != null) {
        await launchUrl(
          Uri.parse(
              '$_stripeTopupLink?client_reference_id=$currentUserId'),
          mode: LaunchMode.externalApplication,
        );
        if (mounted) {
          showInfo(context,
              'Finish the payment on Stripe — your balance updates once it succeeds.');
          Navigator.of(context).pop(true);
        }
        return;
      }
      // Otherwise: Stripe hosted checkout via the backend session endpoint.
      final Map<String, dynamic> session;
      try {
        session =
            await api.payments.checkout({'kind': 'topup', 'amount': amount});
      } on ApiException catch (e) {
        // The known live gap: the backend's checkout handler doesn't accept
        // a wallet top-up yet ("Invalid recipient"). A raw error here leaves
        // the user with no way forward — say what's actually wrong.
        if (mounted) {
          showInfo(
              context,
              'Adding money isn\'t available in this app yet '
              '(server said: ${e.message}). '
              'Please try again later or contact support.');
        }
        return;
      }
      final url = session['url'] ??
          session['checkout_url'] ??
          session['session_url'];
      if (url == null || '$url'.isEmpty) {
        if (mounted) {
          showInfo(context,
              'Checkout is unavailable right now — try again shortly.');
        }
        return;
      }
      // (Backend note: if checkout rejects kind "topup" — e.g. "Invalid
      // recipient" — the server needs a wallet top-up kind; tips/subs
      // checkout requires a recipient.)
      await launchUrl(Uri.parse('$url'),
          mode: LaunchMode.externalApplication);
      if (mounted) {
        showInfo(context,
            'Finish the payment in the secure checkout — your balance updates once it succeeds.');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs the inline web card form (Stripe Payment Element) against a
  /// backend PaymentIntent. paid: true = paid, false = user cancelled,
  /// null = couldn't start ([failure] says why).
  Future<({bool? paid, String? failure})> _inlineWebTopUp(num amount) async {
    final String pk;
    final String secret;
    try {
      // The intent reply carries its own publishable_key; config is only
      // the fallback for older backends.
      final intent = await api.wallet.topupIntent(amount);
      secret =
          '${intent['client_secret'] ?? intent['clientSecret'] ?? intent['payment_intent_client_secret'] ?? ''}';
      if (secret.isEmpty) {
        return (
          paid: null,
          failure: 'The server didn\'t return a payment client secret '
              '(keys in the reply: ${intent.keys.join(', ')}).'
        );
      }
      var key = '${intent['publishable_key'] ?? ''}';
      if (key.isEmpty) {
        final cfg = await api.payments.config();
        key = '${cfg['publishable_key'] ?? ''}';
      }
      if (key.isEmpty) {
        return (
          paid: null,
          failure: 'The server has no Stripe publishable key configured.'
        );
      }
      pk = key;
    } on ApiException catch (e) {
      return (paid: null, failure: 'Starting the top-up failed: ${e.message}');
    } catch (e) {
      return (paid: null, failure: messageFor(e));
    }
    if (!mounted) return (paid: false, failure: null);
    final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _InlineCardPayScreen(
          publishableKey: pk, clientSecret: secret, amount: amount),
    ));
    if (paid == true) {
      // Credit immediately instead of waiting on the webhook.
      final intentId = secret.split('_secret').first;
      try {
        await api.wallet.confirmTopupIntent({'intent_id': intentId});
      } catch (_) {/* topup/sync reconciles on the next wallet load */}
      return (paid: true, failure: null);
    }
    return (paid: false, failure: null); // backed out or cancelled
  }

  /// Runs the native PaymentSheet against a backend PaymentIntent.
  /// Returns true = paid, false = cancelled, null = unavailable.
  Future<bool?> _paySheetTopUp(num amount) async {
    try {
      final cfg = await api.payments.config();
      final pk = '${cfg['publishable_key'] ?? ''}';
      if (pk.isEmpty) return null;
      final intent = await api.wallet.topupIntent(amount);
      final secret = '${intent['client_secret'] ?? intent['clientSecret'] ?? intent['payment_intent_client_secret'] ?? ''}';
      if (secret.isEmpty) return null;
      final paid =
          await stripePaySheet(publishableKey: pk, clientSecret: secret);
      if (paid) {
        // Credit immediately instead of waiting on the webhook; the id is
        // the client secret's prefix (pi_..._secret_... → pi_...).
        final intentId = secret.split('_secret').first;
        try {
          await api.wallet.confirmTopupIntent({'intent_id': intentId});
        } catch (_) {/* webhook will reconcile */}
      }
      return paid;
    } on Exception {
      // A sheet failure (transient Stripe/network error) must not dead-end
      // the flow: null sends the caller down the hosted fallbacks. False is
      // reserved for a deliberate user cancel.
      return null;
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

  /// Set when a top-up was cancelled, so the wallet reloads on pop.
  bool _changed = false;

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
        _changed = true;
        setState(_load);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
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
      ),
    );
  }
}

/// The full wallet activity feed (`/wallet/activity`) — everything, not just
/// the recent slice on the overview. Reuses the overview's transaction tiles,
/// so the detail sheet / send-again work here too.
class WalletActivityScreen extends StatefulWidget {
  const WalletActivityScreen({super.key});

  @override
  State<WalletActivityScreen> createState() => _WalletActivityScreenState();
}

class _WalletActivityScreenState extends State<WalletActivityScreen> {
  late Future<List<WalletTxn>> _activity = _fetch();

  /// Set when something here changed the wallet (e.g. send-again), so the
  /// overview reloads when this screen pops.
  bool _changed = false;

  Future<List<WalletTxn>> _fetch() async {
    final raw = await api.wallet.activity();
    final maps = _mapList(raw, 'activity');
    return maps.map(WalletTxn.fromJson).toList()..sort(_byNewest);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _activity = _fetch());
    try {
      await _activity;
    } catch (_) {}
  }

  void _onChanged() {
    _changed = true;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
      appBar: const OkayAppBar(title: Text('All activity')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<WalletTxn>>(
            future: _activity,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return CenteredMessage(
                    message: messageFor(snapshot.error),
                    icon: Icons.error_outline,
                    onRetry: _reload);
              }
              final txns = snapshot.data ?? const <WalletTxn>[];
              if (txns.isEmpty) {
                return const CenteredMessage(
                    message: 'No activity yet.',
                    icon: Icons.receipt_long_outlined);
              }
              final now = DateTime.now();
              final children = <Widget>[];
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
                  children.add(Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
                    child: Text(label,
                        style: TextStyle(
                            color: scheme.outline,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4)),
                  ));
                }
                children.add(_TxnTile(txn: t, onChanged: _onChanged));
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: children,
              );
            },
          ),
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

  /// Recent transactions, used for the "between you and X" history.
  List<WalletTxn> _recentTxns = const [];

  static const _presets = [5, 10, 20, 50, 100];

  @override
  void initState() {
    super.initState();
    api.wallet.summary().then((w) {
      if (mounted) {
        setState(() {
          _balance = w.balance;
          _currency = w.currency;
          _recentTxns = [...w.recent, ...w.sent]..sort(_byNewest);
        });
      }
    }).catchError((_) {});
  }

  /// Past transactions with the selected recipient, newest first, deduped by
  /// id (recent + sent can overlap in the summary payload).
  List<WalletTxn> get _betweenUs {
    if (_recipient == null) return const [];
    final seen = <String>{};
    return _recentTxns
        .where((t) =>
            t.counterpartyId == _recipient!.userId &&
            (t.id == null || seen.add(t.id!)))
        .take(3)
        .toList();
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
    if (_recipient == null ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0) {
      showInfo(context, 'Pick a recipient and a valid amount.');
      return;
    }
    if (_overBalance) {
      showInfo(context, 'That\'s more than your available balance.');
      return;
    }
    // Self-imposed spending limits: warn before crossing one, but let the
    // user override — it's their own cap.
    final exceeded = spendingLimits.wouldExceed(_recentTxns, amount);
    if (exceeded != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Spending limit reached'),
          content: Text(
              'This payment takes ${exceeded.label.toLowerCase()}\'s spending '
              'to ${formatMoney(exceeded.spent + amount, _currency)} of your '
              '${formatMoney(exceeded.limit, _currency)} limit. Send anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Send anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final confirmed = await _confirmPayment(context,
        to: _recipient!, amount: amount, currency: _currency, note: note);
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      // Stripe rails first (/stripe/transfer); the ledger transfer remains
      // the fallback for backends without the Stripe Connect endpoints.
      try {
        await api.payments.stripeTransfer(
          toUserId: _recipient!.userId,
          amount: amount,
          note: note,
        );
      } on ApiException catch (e) {
        if (e.isNotFound || e.statusCode == 405 || e.statusCode == 501) {
          await api.wallet.sendMoney(
            toUserId: _recipient!.userId,
            amount: amount,
            answer: _answer.text.trim(),
            note: note,
          );
        } else {
          rethrow;
        }
      }
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
                  final users = (snapshot.data ?? const <PublicUser>[])
                      .where((u) => u.userId != currentUserId)
                      .toList();
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
            // Venmo-style mini history with this person.
            if (_betweenUs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Between you and ${_recipient!.name.split(' ').first}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    for (final t in _betweenUs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                [
                                  t.amount >= 0
                                      ? 'They paid you'
                                      : 'You paid them',
                                  if (t.note != null && t.note!.isNotEmpty)
                                    t.note!,
                                  if (t.createdAt != null)
                                    shortAgo(t.createdAt!),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${t.amount >= 0 ? '+' : '−'} ${_money(t.amount.abs(), t.currency)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: t.amount >= 0
                                      ? const Color(0xFF22C55E)
                                      : Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Venmo-style amount entry: big centered display over a keypad.
            Text(
              '${currencySymbol(_currency)}${_amount.text.isEmpty ? '0' : _amount.text}',
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
    if (_from == null || amount == null || !amount.isFinite || amount <= 0) {
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
                  final users = (snapshot.data ?? const <PublicUser>[])
                      .where((u) => u.userId != currentUserId)
                      .toList();
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

/// Inline card payment: Stripe's Payment Element rendered inside the app
/// (web). Pops `true` once the payment succeeds.
class _InlineCardPayScreen extends StatefulWidget {
  const _InlineCardPayScreen({
    required this.publishableKey,
    required this.clientSecret,
    required this.amount,
  });

  final String publishableKey;
  final String clientSecret;
  final num amount;

  @override
  State<_InlineCardPayScreen> createState() => _InlineCardPayScreenState();
}

class _InlineCardPayScreenState extends State<_InlineCardPayScreen> {
  StripeElementsHandle? _handle;
  String? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  Future<void> _mount() async {
    try {
      final h = await createPaymentElement(
        publishableKey: widget.publishableKey,
        clientSecret: widget.clientSecret,
      );
      if (mounted) setState(() => _handle = h);
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
    }
  }

  Future<void> _pay() async {
    final h = _handle;
    if (h == null || _paying) return;
    setState(() => _paying = true);
    final err = await h.confirm();
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _paying = false);
      showInfo(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = _handle;
    return Scaffold(
      appBar: OkayAppBar(
          title: Text('Pay \$${widget.amount.toStringAsFixed(2)}')),
      body: _error != null
          ? CenteredMessage(
              message: 'The card form couldn\'t load.\n$_error',
              icon: Icons.error_outline)
          : h == null
              ? const Center(child: CircularProgressIndicator())
              : MaxWidth(
                  child: Column(
                    children: [
                      // Stripe's iframe owns the card fields; give it room
                      // to expand (some methods add extra inputs).
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: h.view)),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.icon(
                                onPressed: _paying ? null : _pay,
                                icon: _paying
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.lock_outline),
                                label: Text(_paying
                                    ? 'Processing…'
                                    : 'Pay \$${widget.amount.toStringAsFixed(2)}'),
                              ),
                              const SizedBox(height: 8),
                              Text('Card details are processed by Stripe.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 11)),
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
