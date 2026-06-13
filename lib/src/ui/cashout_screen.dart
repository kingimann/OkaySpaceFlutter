import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../okayspace_api.dart';
import '../core/stripe_connect_embed.dart';
import '../core/stripe_elements.dart';
import 'common.dart';
import 'money_guards.dart';

/// Stripe-backed payouts: onboarding status, identity verification, and
/// cashing out the available balance.
class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key});

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final _amount = TextEditingController();
  Map<String, dynamic> _status = const {};
  bool _loading = true;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadConfig();
    _loadMethods();
  }

  /// Saved payout destinations ("Visa •• 4242 · default").
  List<Map<String, dynamic>> _methods = const [];

  Future<void> _loadMethods() async {
    try {
      final raw = await api.payments.payoutMethods();
      final list = raw is Map
          ? (raw['data'] ?? raw['methods'] ?? raw['items'])
          : raw;
      if (list is List && mounted) {
        setState(() => _methods = [
              for (final m in list.whereType<Map>())
                m.cast<String, dynamic>(),
            ]);
      }
    } catch (_) {/* endpoint optional; the section just stays hidden */}
  }

  Future<void> _methodAction(Map<String, dynamic> m, String action) async {
    final id = '${m['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (action == 'default') {
        await api.payments.setDefaultPayoutMethod(id);
        if (mounted) showInfo(context, 'Default payout method updated');
      } else if (action == 'remove') {
        await api.payments.deletePayoutMethod(id);
        if (mounted) showInfo(context, 'Payout method removed');
      }
      await _loadMethods();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  // The money lives in two pots: the in-app wallet ledger (cashed out via
  // /payments/payouts/cashout) and the user's Stripe balance from received
  // transfers (paid out via /stripe/payout). payouts/status carries no
  // balance at all.
  num _ledger = 0;
  num _stripeAvail = 0;
  num _stripePending = 0;
  bool _gotBalance = false;

  Future<void> _load() async {
    // Full-screen spinner only before the first payload; refreshes keep the
    // current UI (so pull-to-refresh isn't torn down mid-gesture).
    if (_status.isEmpty && !_error) setState(() => _loading = true);
    try {
      _status = await api.payments.payoutStatus();
      _error = false;
      final sched = '${_status['payout_schedule'] ?? _status['schedule'] ?? _status['payout_interval'] ?? ''}'
          .toLowerCase();
      if (const ['manual', 'weekly', 'biweekly', 'monthly']
          .contains(sched)) {
        _schedule = sched;
      }
    } catch (_) {
      // A failed load must read as an error, not as a $0 balance.
      if (_status.isEmpty) _error = true;
    }
    try {
      final b = await api.wallet.balance();
      final v = b is Map ? b['balance'] : null;
      if (v is num) {
        _ledger = v;
        _gotBalance = true;
      }
    } catch (_) {/* ledger balance unavailable */}
    try {
      final s = await api.payments.stripeBalance();
      if (s['connected'] == true) {
        _stripeAvail = s['available'] is num ? s['available'] as num : 0;
        _stripePending = s['pending'] is num ? s['pending'] as num : 0;
      }
      _gotBalance = true;
    } catch (_) {/* stripe balance unavailable */}
    try {
      final s = await api.payments.payoutSchedule();
      final interval = '${s['interval'] ?? ''}'.toLowerCase();
      if (const ['manual', 'weekly', 'biweekly', 'monthly']
          .contains(interval)) {
        _schedule = interval;
      }
    } catch (_) {/* schedule endpoint optional */}
    if (mounted) setState(() => _loading = false);
  }

  bool get _ready =>
      _status['payouts_enabled'] == true ||
      _status['ready'] == true ||
      _status['charges_enabled'] == true;

  num get _available {
    final v = _status['available'] ??
        _status['balance'] ??
        _status['payout_balance'];
    final legacy = v is num ? v : num.tryParse('$v');
    return legacy ?? (_ledger + _stripeAvail);
  }

  String get _symbol =>
      currencySymbol('${_status['currency'] ?? 'USD'}'.toUpperCase());

  /// Opens payout setup/management. On the web the Stripe form is embedded
  /// inside the app (Connect.js + the backend account-session); if the embed
  /// can't start, or on native, Stripe's hosted link opens instead.
  Future<void> _setup({String component = 'account-onboarding'}) async {
    if (stripeEmbedSupported) {
      final embedded = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
            builder: (_) => EmbeddedPayoutScreen(component: component)),
      );
      if (embedded == true) {
        await _load();
        await _loadMethods();
        return;
      }
      // Backing out (null) is a cancel — never auto-open a browser. Only
      // an explicit "Open on Stripe instead" (false) reaches the hosted
      // flow.
      if (embedded == null || !mounted) return;
    }
    await _setupHosted();
  }

  /// In-app chooser for payout destinations: debit card (instant) or bank
  /// account (direct deposit), both as native forms. Stripe's embedded
  /// form remains a labeled advanced option.
  Future<void> _payoutMethodChooser() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Payout method',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.credit_card_outlined),
              title: const Text('Debit card'),
              subtitle: const Text('Instant payouts — minutes'),
              onTap: () => Navigator.pop(sheetContext, 'card'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Bank account (direct deposit)'),
              subtitle: const Text('Standard payouts — 1–2 business days'),
              onTap: () => Navigator.pop(sheetContext, 'bank'),
            ),
            // No "Stripe form" option: for Express accounts Stripe's
            // embedded components delegate data entry to their hosted page
            // (account-type limitation) — everything users need is covered
            // by the in-app forms above and the identity modal below.
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Verify identity'),
              subtitle: const Text('Government ID + selfie, in-app'),
              onTap: () => Navigator.pop(sheetContext, 'identity'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'card':
        await _addDebitCard();
      case 'bank':
        await _addBankAccount();
      case 'identity':
        await _verifyIdentity();
    }
  }

  /// In-app direct-deposit form: routing/account fields here, tokenized by
  /// Stripe, attached via the backend. No browser.
  Future<void> _addBankAccount() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddBankAccountScreen()),
    );
    if (added == true) {
      await _load();
      await _loadMethods();
    }
  }

  /// DoorDash-style: an in-app card form tokenizes the debit card with
  /// Stripe and the backend attaches it as the instant-payout destination.
  /// No browser involved.
  Future<void> _addDebitCard() async {
    if (stripeElementsSupported) {
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AddPayoutCardScreen()),
      );
      if (added == true) {
        await _load();
        await _loadMethods();
      }
      return;
    }
    // Native fallback until the in-app native card form ships.
    await launchUrl(
      Uri.parse('https://connect.stripe.com/express_login'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _setupHosted() async {
    setState(() => _busy = true);
    try {
      final res = await api.payments.setupPayouts();
      final url = res['url'] ?? res['onboarding_url'] ?? res['account_link'];
      if (!mounted) return;
      if (url != null) {
        // Open Stripe onboarding directly; clipboard is the fallback.
        final opened = await launchUrl(Uri.parse('$url'),
            mode: LaunchMode.externalApplication);
        if (!mounted) return;
        if (!opened) {
          await Clipboard.setData(ClipboardData(text: '$url'));
          if (mounted) {
            showInfo(context,
                'Onboarding link copied — open it in a browser to finish setup.');
          }
        } else {
          showInfo(context,
              'Finish the Stripe onboarding, then pull to refresh here.');
        }
      } else {
        showInfo(context, 'Payout setup started.');
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyIdentity() async {
    setState(() => _busy = true);
    try {
      final res = await api.payments.startIdentity();
      if (!mounted) return;
      if (res['already_verified'] == true) {
        showInfo(context, 'Your identity is already verified ✓');
        await _load();
        return;
      }
      // In-app first: Stripe Identity's in-page modal needs the
      // verification session's client secret.
      final vSecret = '${res['client_secret'] ?? res['clientSecret'] ?? ''}';
      if (stripeElementsSupported && vSecret.isNotEmpty) {
        final cfg = await api.payments.config();
        final pk = '${cfg['publishable_key'] ?? ''}';
        if (pk.isNotEmpty) {
          final err = await stripeVerifyIdentityModal(
              publishableKey: pk, clientSecret: vSecret);
          if (!mounted) return;
          if (err == null) {
            showInfo(context,
                'Thanks — verification is processing. Pull to refresh.');
            await _load();
            return;
          }
          // The modal couldn't run (e.g. Stripe Identity not activated on
          // the platform account, or the session was rejected). Offer the
          // hosted page when one exists — explicit choice, not automatic.
          final url = '${res['url'] ?? res['verification_url'] ?? ''}';
          if (url.startsWith('http')) {
            final useHosted = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('In-app verification unavailable'),
                content: Text('$err\n\n'
                    'You can finish on Stripe\'s secure verification page '
                    'instead.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Open Stripe page')),
                ],
              ),
            );
            if (useHosted == true && mounted) {
              await launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication);
            }
          } else {
            showInfo(context, err);
          }
          return;
        }
      }
      final url = res['url'] ?? res['verification_url'];
      if (!mounted) return;
      if (url != null && '$url'.startsWith('http')) {
        final opened = await launchUrl(Uri.parse('$url'),
            mode: LaunchMode.externalApplication);
        if (!mounted) return;
        if (!opened) {
          await Clipboard.setData(ClipboardData(text: '$url'));
          if (mounted) {
            showInfo(
                context, 'Verification link copied — open it to continue.');
          }
        } else {
          showInfo(context,
              'Finish the verification, then pull to refresh here.');
        }
      } else {
        showInfo(context, 'Identity verification started.');
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Cash-out limits from /payments/config; defaults match the platform's
  // published policy ($20 minimum, $2 flat fee) until the config loads.
  num _fee = 2.00;
  num _min = 20.0;

  Future<void> _loadConfig() async {
    try {
      final cfg = await api.payments.config();
      if (!mounted) return;
      setState(() {
        _fee = cfg['cashout_fee'] is num ? cfg['cashout_fee'] as num : _fee;
        _min = cfg['cashout_min'] is num ? cfg['cashout_min'] as num : _min;
      });
    } catch (_) {/* keep defaults */}
    // Feature discovery: hide the Instant toggle on backends without
    // Stripe Instant Payouts (stays visible if the probe fails).
    try {
      final caps = await api.payments.capabilities();
      if (mounted && caps['instant_payouts'] == false) {
        setState(() {
          _instantAllowed = false;
          _instant = false;
        });
      }
    } catch (_) {/* capabilities endpoint optional */}
  }

  bool _instantAllowed = true;

  /// Instant payouts require a debit card on file (Stripe rule).
  bool get _hasDebitCard =>
      _status['has_debit_card'] == true ||
      _methods.any((m) => '${m['type']}' == 'card');

  // Automatic payout schedule (manual = only when the user cashes out).
  String _schedule = 'manual';
  bool _savingSchedule = false;

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// Weekly/biweekly need a payout day; monthly needs a day-of-month.
  Future<({String? weekly, int? monthly})?> _askAnchor(String interval) async {
    if (interval == 'weekly' || interval == 'biweekly') {
      final day = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                  title: Text('Pay me on',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              for (final d in _weekdays)
                ListTile(
                  title: Text(d[0].toUpperCase() + d.substring(1)),
                  onTap: () => Navigator.pop(sheetContext, d),
                ),
            ],
          ),
        ),
      );
      return day == null ? null : (weekly: day, monthly: null);
    }
    if (interval == 'monthly') {
      var day = 1;
      final picked = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialog) => AlertDialog(
            title: const Text('Pay me on day of month'),
            content: DropdownButton<int>(
              value: day,
              isExpanded: true,
              items: [
                for (var i = 1; i <= 28; i++)
                  DropdownMenuItem(value: i, child: Text('Day $i')),
              ],
              onChanged: (v) => setDialog(() => day = v ?? 1),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, day),
                  child: const Text('Set')),
            ],
          ),
        ),
      );
      return picked == null ? null : (weekly: null, monthly: picked);
    }
    return (weekly: null, monthly: null); // manual
  }

  Future<void> _setSchedule(String interval) async {
    final previous = _schedule;
    // Collect the payout day before committing (weekly/monthly require it).
    final anchor = await _askAnchor(interval);
    if (anchor == null || !mounted) return; // user backed out of the picker
    setState(() {
      _schedule = interval;
      _savingSchedule = true;
    });
    try {
      await api.payments.setPayoutSchedule(
        interval,
        weeklyAnchor: anchor.weekly,
        monthlyAnchor: anchor.monthly,
      );
      if (mounted) {
        showInfo(
            context,
            interval == 'manual'
                ? 'Automatic payouts off — cash out whenever you like.'
                : 'You\'ll be paid ${switch (interval) {
                    'weekly' => 'every ${anchor.weekly}',
                    'biweekly' => 'every two weeks on ${anchor.weekly}',
                    _ => 'monthly on day ${anchor.monthly}',
                  }} automatically.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _schedule = previous);
        showInfo(
            context,
            e.isNotFound
                ? 'Payout schedules aren\'t supported by the server yet.'
                : e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _schedule = previous);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _savingSchedule = false);
    }
  }

  num? get _entered => num.tryParse(_amount.text.trim());

  /// Whether any balance source actually answered (0 may mean "unknown").
  bool get _knowsBalance =>
      _gotBalance ||
      _status['available'] != null ||
      _status['balance'] != null ||
      _status['payout_balance'] != null;

  bool get _overAvailable =>
      _knowsBalance && (_entered ?? 0) > _available;

  Future<void> _cashout() async {
    final amount = _entered;
    if (amount == null || !amount.isFinite || amount < _min) {
      showInfo(context,
          'Minimum cash-out is $_symbol${_min.toStringAsFixed(2)}.');
      return;
    }
    if (_overAvailable) {
      showInfo(context, 'That\'s more than your available balance.');
      return;
    }
    // The backend config doesn't guarantee fee < min; never let a cash-out
    // through where the fee eats the whole amount.
    if (amount <= _fee) {
      showInfo(context,
          'Amount must be more than the $_symbol${_fee.toStringAsFixed(2)} fee.');
      return;
    }
    // Instant payouts can only land on a debit card.
    if (_instant && !_hasDebitCard) {
      showInfo(context,
          'Add a debit card first — instant payouts can\'t go to a bank '
          'account.');
      return;
    }
    // Guards: fat-finger confirm on big amounts, repeat detection.
    if (!await confirmLargeAmount(context, amount) || !mounted) return;
    final dupKey = 'cashout:$amount';
    if (isRecentDuplicate(dupKey)) {
      final repeat = await confirmDuplicate(context,
          'requested a $_symbol${amount.toStringAsFixed(2)} cash-out');
      if (!repeat || !mounted) return;
    }
    markMoneyAction(dupKey);
    setState(() => _busy = true);
    try {
      // Route to the pot that holds the money: the in-app ledger uses the
      // DoorDash-style cash-out endpoint; the Stripe balance (received
      // transfers) pays out via /stripe/payout.
      if (amount <= _ledger || _stripeAvail <= 0) {
        await api.payments.cashout({'amount': amount});
      } else if (amount <= _stripeAvail) {
        await api.payments.stripePayout(amount: amount, instant: _instant);
      } else {
        showInfo(
            context,
            'That amount spans both balances — cash out up to '
            '$_symbol${_ledger.toStringAsFixed(2)} (in-app) or '
            '$_symbol${_stripeAvail.toStringAsFixed(2)} (Stripe) at once.');
        setState(() => _busy = false);
        return;
      }
      if (mounted) {
        showInfo(
            context,
            _instant
                ? 'Instant payout requested — usually minutes to your card.'
                : 'Cash-out requested');
        _amount.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Instant payouts hit the debit card in minutes (Stripe charges its
  // instant fee); standard payouts take 1-2 business days.
  bool _instant = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Cash out')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error && _status.isEmpty
              ? CenteredMessage(
                  message: 'Couldn\'t load your payout status.',
                  icon: Icons.error_outline,
                  onRetry: _load)
              : MaxWidth(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Available payout balance.
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primary,
                            darken(scheme.primary, 0.22)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Available to cash out',
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.85))),
                          const SizedBox(height: 8),
                          Text('$_symbol${_available.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold)),
                          if (_stripeAvail > 0 || _stripePending > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                  'In-app $_symbol${_ledger.toStringAsFixed(2)}'
                                  ' · Stripe $_symbol${_stripeAvail.toStringAsFixed(2)}'
                                  '${_stripePending > 0 ? ' (+$_symbol${_stripePending.toStringAsFixed(2)} pending)' : ''}',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Onboarding status banner.
                    if (!_ready)
                      Card(
                        color: scheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: scheme.primary),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                        'Set up payouts to cash out',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                  'Verify your identity and link a payout '
                                  'destination to receive money.'),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _busy ? null : () => _setup(),
                                    icon: const Icon(Icons.account_balance),
                                    label: const Text('Set up payouts'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : _verifyIdentity,
                                    icon: const Icon(Icons.badge_outlined),
                                    label: const Text('Verify identity'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_ready) ...[
                      // Saved payout destinations, DoorDash-style.
                      if (_methods.isNotEmpty)
                        Card(
                          child: Column(
                            children: [
                              for (final m in _methods)
                                ListTile(
                                  dense: true,
                                  leading: Icon(
                                      '${m['type']}' == 'card'
                                          ? Icons.credit_card
                                          : Icons.account_balance,
                                      color: scheme.primary),
                                  title: Text(
                                      '${(m['brand'] ?? m['bank_name'] ?? 'Account').toString().toUpperCase()} '
                                      '•• ${m['last4'] ?? '????'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  subtitle: Text([
                                    if (m['default'] == true) 'Default',
                                    if (m['instant_eligible'] == true)
                                      'Instant eligible',
                                    if ('${m['type']}' == 'bank_account')
                                      '1–2 business days',
                                  ].join(' · ')),
                                  trailing: PopupMenuButton<String>(
                                    enabled: !_busy,
                                    onSelected: (a) => _methodAction(m, a),
                                    itemBuilder: (_) => [
                                      if (m['default'] != true)
                                        const PopupMenuItem(
                                            value: 'default',
                                            child: Text('Make default')),
                                      const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove')),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      // Bank / debit card on file — managed via Stripe's
                      // account-update link (same flow as onboarding).
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.account_balance_outlined,
                              color: scheme.primary),
                          title: const Text('Payout method'),
                          subtitle: const Text(
                              'Add or change your bank account or debit card'),
                          trailing: Icon(Icons.chevron_right,
                              size: 20, color: scheme.outline),
                          onTap: _busy ? null : _payoutMethodChooser,
                        ),
                      ),
                      // Debit cards (instant payouts): embedded payouts
                      // dashboard when supported; the Stripe Express login
                      // is the external fallback.
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.credit_card_outlined,
                              color: scheme.primary),
                          title: const Text('Add a debit card'),
                          subtitle:
                              const Text('For instant payouts to your card'),
                          trailing: Icon(
                              stripeEmbedSupported
                                  ? Icons.chevron_right
                                  : Icons.open_in_new,
                              size: 18,
                              color: scheme.outline),
                          onTap: _busy ? null : _addDebitCard,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Amount to cash out',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.attach_money),
                          hintText: '0.00',
                          border: const OutlineInputBorder(),
                          errorText: _overAvailable
                              ? 'More than your available balance'
                              : null,
                          helperText: (_entered ?? 0) >= _min &&
                                  (_entered ?? 0) > _fee &&
                                  !_overAvailable
                              ? "You'll receive "
                                  '$_symbol${(_entered! - _fee).toStringAsFixed(2)} '
                                  'after the $_symbol${_fee.toStringAsFixed(2)} fee'
                              : '$_symbol${_min.toStringAsFixed(0)} minimum · '
                                  '$_symbol${_fee.toStringAsFixed(2)} flat fee · instant to debit card',
                        ),
                      ),
                      if (_available >= 5) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (label, frac) in const [
                              ('25%', 0.25),
                              ('50%', 0.5),
                              ('Max', 1.0)
                            ])
                              ActionChip(
                                label: Text(label),
                                onPressed: () => setState(() => _amount.text =
                                    (_available * frac).toStringAsFixed(2)),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_instantAllowed)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Instant to debit card'),
                          subtitle: Text(_hasDebitCard
                              ? 'Minutes instead of 1–2 business days '
                                  '(Stripe instant fee applies)'
                              : 'Add a debit card first — instant payouts '
                                  'can\'t go to a bank account'),
                          value: _instant && _hasDebitCard,
                          onChanged: _busy
                              ? null
                              : (v) {
                                  if (v && !_hasDebitCard) {
                                    _addDebitCard();
                                    return;
                                  }
                                  setState(() => _instant = v);
                                },
                        ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _cashout,
                        icon: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.payments_outlined),
                        label: const Text('Cash out'),
                      ),
                      const SizedBox(height: 20),
                      // Automatic payout schedule.
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Get paid automatically',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                  'Your balance pays out to your bank on a '
                                  'schedule — or keep it manual and cash '
                                  'out whenever you like.',
                                  style: TextStyle(
                                      color: scheme.outline,
                                      fontSize: 12.5)),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final (id, label) in const [
                                    ('manual', 'Manual'),
                                    ('weekly', 'Weekly'),
                                    ('biweekly', 'Every 2 weeks'),
                                    ('monthly', 'Monthly'),
                                  ])
                                    ChoiceChip(
                                      label: Text(label),
                                      selected: _schedule == id,
                                      onSelected: _savingSchedule ||
                                              _schedule == id
                                          ? null
                                          : (_) => _setSchedule(id),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// Stripe's payout forms (onboarding / account management) embedded inside
/// the app via Connect.js — web only. Pops `true` after the user finishes,
/// `false` when the embed can't start so the caller can fall back to the
/// hosted Stripe link.
class EmbeddedPayoutScreen extends StatefulWidget {
  const EmbeddedPayoutScreen({super.key, required this.component});

  /// 'account-onboarding' (first-time setup) or 'account-management'
  /// (edit bank account / debit card).
  final String component;

  @override
  State<EmbeddedPayoutScreen> createState() => _EmbeddedPayoutScreenState();
}

class _EmbeddedPayoutScreenState extends State<EmbeddedPayoutScreen> {
  String? _publishableKey;
  String? _firstSecret;
  String? _error;
  bool _popped = false;
  int _attempt = 0; // bumps the view so Retry rebuilds it from scratch

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Pre-validates everything the embed needs (publishable key AND a
  /// working account session) so a backend gap shows a real error screen
  /// instead of a blank page.
  Future<void> _start() async {
    setState(() {
      _error = null;
      _publishableKey = null;
      _firstSecret = null;
    });
    try {
      final cfg = await api.payments.config();
      final pk = '${cfg['publishable_key'] ?? ''}';
      if (pk.isEmpty) throw StateError('No Stripe publishable key');
      final session = await api.payments.payoutAccountSession();
      final secret = _secretOf(session);
      // The backend reports which embedded components the session enables
      // (e.g. the full 'payouts' dashboard vs onboarding-only); honor it.
      final enabled = _componentsOf(session['components']);
      if (!mounted) return;
      setState(() {
        _publishableKey = pk;
        _firstSecret = secret;
        _enabled = enabled;
        _attempt++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
    }
  }

  List<String> _enabled = const [];

  /// Normalizes the session's enabled-components payload. Accepts a list of
  /// names, a {name: bool} map, or a list of {name/enabled} maps, in either
  /// Stripe-API (account_management) or Connect.js (account-management)
  /// spelling — comparison happens dashed-lowercase.
  static List<String> _componentsOf(Object? raw) {
    String norm(Object? v) =>
        '$v'.trim().toLowerCase().replaceAll('_', '-');
    if (raw is Map) {
      return [
        for (final e in raw.entries)
          if (e.value == true || e.value is Map) norm(e.key),
      ];
    }
    if (raw is List) {
      return [
        for (final c in raw)
          if (c is Map)
            norm(c['name'] ?? c['component'] ?? c.keys.firstOrNull)
          else
            norm(c),
      ];
    }
    return const [];
  }

  /// The component to render: the requested one when the session enables it,
  /// otherwise the best enabled alternative ('payouts' is the full embedded
  /// dashboard: payout methods, balance, and instant payouts). Stripe renders
  /// non-enabled components as a silent blank, so this choice matters.
  String get _component {
    if (_enabled.isEmpty || _enabled.contains(widget.component)) {
      return widget.component;
    }
    for (final c in ['payouts', 'account-management', 'account-onboarding']) {
      if (_enabled.contains(c)) return c;
    }
    return widget.component;
  }

  String _secretOf(Map<String, dynamic> s) {
    final secret =
        '${s['client_secret'] ?? s['clientSecret'] ?? s['secret'] ?? ''}';
    if (secret.isEmpty) {
      throw StateError(
          'The server returned no account-session client secret');
    }
    return secret;
  }

  Future<String> _freshSecret() async =>
      _secretOf(await api.payments.payoutAccountSession());

  /// First call uses the pre-validated secret; Connect.js re-asks when a
  /// session expires, and then we mint a fresh one.
  Future<String> _clientSecret() async {
    final first = _firstSecret;
    if (first != null) {
      _firstSecret = null;
      return first;
    }
    return _freshSecret();
  }

  /// Leaves the screen signalling "use the hosted link instead".
  void _bail() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(false);
  }

  void _done() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final pk = _publishableKey;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(widget.component == 'account-management'
            ? 'Payout method'
            : 'Set up payouts'),
        actions: [
          TextButton(
            onPressed: _done,
            child: const Text('Done'),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 40, color: scheme.error),
                    const SizedBox(height: 12),
                    Text('The Stripe form couldn\'t load.\n$_error',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _bail,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open on Stripe instead'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : pk == null
              ? const Center(child: CircularProgressIndicator())
              // The Stripe component manages its own scrolling. KeyedSubtree
              // forces a fresh platform view per attempt.
              : KeyedSubtree(
                  key: ValueKey(_attempt),
                  child: SizedBox.expand(
                    child: stripeConnectView(
                      publishableKey: pk,
                      fetchClientSecret: _clientSecret,
                      component: _component,
                      // The session may not have this component enabled;
                      // onboarding is the universal fallback.
                      fallbackComponent: _component == 'account-management'
                          ? 'account-onboarding'
                          : null,
                      onExit: () {
                        // Connect.js calls this off the Flutter frame; defer.
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _done());
                      },
                      onError: (msg) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _error = msg);
                        });
                      },
                    ),
                  ),
                ),
    );
  }
}

/// In-app debit-card entry for instant payouts (DoorDash-style): Stripe's
/// card Element tokenizes the number in its iframe and the backend attaches
/// the token as the payout destination. No browser, no hosted page.
class AddPayoutCardScreen extends StatefulWidget {
  const AddPayoutCardScreen({super.key});

  @override
  State<AddPayoutCardScreen> createState() => _AddPayoutCardScreenState();
}

class _AddPayoutCardScreenState extends State<AddPayoutCardScreen> {
  StripeCardTokenHandle? _card;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final cfg = await api.payments.config();
      final pk = '${cfg['publishable_key'] ?? ''}';
      if (pk.isEmpty) throw StateError('No Stripe publishable key');
      final card = await createCardTokenElement(publishableKey: pk);
      if (mounted) setState(() => _card = card);
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
    }
  }

  Future<void> _save() async {
    final card = _card;
    if (card == null || _saving) return;
    setState(() => _saving = true);
    try {
      final t = await card.tokenize();
      if (!mounted) return;
      final token = t.token;
      if (token == null) {
        showInfo(context, t.error ?? 'Check the card details.');
        return;
      }
      await api.payments.addDebitCard(token);
      if (mounted) {
        showInfo(context, 'Debit card added — instant payouts enabled.');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = _card;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Add a debit card')),
      body: MaxWidth(
        child: _error != null
            ? CenteredMessage(
                message: 'The card form couldn\'t load.\n$_error',
                icon: Icons.error_outline,
                onRetry: _start)
            : card == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Card for instant payouts',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                          'Use a Visa or Mastercard debit card. Cash-outs '
                          'with "Instant" arrive in minutes.',
                          style: TextStyle(
                              color: scheme.outline, fontSize: 12.5)),
                      const SizedBox(height: 16),
                      card.view,
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.lock_outline),
                        label:
                            Text(_saving ? 'Saving…' : 'Save debit card'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                          'Card details go directly to Stripe — OkaySpace '
                          'never sees the number.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: scheme.outline, fontSize: 11)),
                    ],
                  ),
      ),
    );
  }
}

/// In-app direct-deposit setup: the user types their bank details into the
/// app's own fields, Stripe tokenizes them client-side, and the backend
/// attaches the token as the payout destination. DoorDash-style — no
/// browser, no hosted page.
class AddBankAccountScreen extends StatefulWidget {
  const AddBankAccountScreen({super.key});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final _name = TextEditingController();
  final _routing = TextEditingController();
  final _account = TextEditingController();
  final _confirm = TextEditingController();
  String _country = 'CA';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _routing.dispose();
    _account.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final routing = _routing.text.trim();
    final account = _account.text.trim();
    if (name.isEmpty || routing.isEmpty || account.isEmpty) {
      showInfo(context, 'Fill in every field.');
      return;
    }
    if (account != _confirm.text.trim()) {
      showInfo(context, 'The account numbers don\'t match.');
      return;
    }
    setState(() => _saving = true);
    try {
      final cfg = await api.payments.config();
      final pk = '${cfg['publishable_key'] ?? ''}';
      if (pk.isEmpty) throw StateError('No Stripe publishable key');
      final t = await createBankToken(
        publishableKey: pk,
        country: _country,
        currency: _country == 'CA' ? 'cad' : 'usd',
        routingNumber: routing,
        accountNumber: account,
        holderName: name,
      );
      if (!mounted) return;
      final token = t.token;
      if (token == null) {
        showInfo(context, t.error ?? 'Check the bank details.');
        return;
      }
      await api.payments.addBankAccount(token);
      if (mounted) {
        showInfo(context, 'Bank account added for direct deposit.');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Direct deposit')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Bank account for payouts',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
                'Standard payouts arrive in 1–2 business days, no fee from '
                'Stripe for standard transfers.',
                style: TextStyle(color: scheme.outline, fontSize: 12.5)),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'CA', label: Text('Canada')),
                ButtonSegment(value: 'US', label: Text('United States')),
              ],
              selected: {_country},
              onSelectionChanged: (s) => setState(() => _country = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Account holder name',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _routing,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: _country == 'CA'
                      ? 'Transit-institution number'
                      : 'Routing number',
                  helperText: _country == 'CA'
                      ? '5-digit transit + 3-digit institution, e.g. 12345-678'
                      : '9-digit ABA routing number',
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _account,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Account number', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Confirm account number',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline),
              label: Text(_saving ? 'Saving…' : 'Save bank account'),
            ),
            const SizedBox(height: 10),
            Text(
                'Bank details are tokenized by Stripe in your browser — '
                'OkaySpace servers never store the numbers.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
