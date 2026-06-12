import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../okayspace_api.dart';
import '../core/stripe_connect_embed.dart';
import 'common.dart';

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
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Full-screen spinner only before the first payload; refreshes keep the
    // current UI (so pull-to-refresh isn't torn down mid-gesture).
    if (_status.isEmpty && !_error) setState(() => _loading = true);
    try {
      _status = await api.payments.payoutStatus();
      _error = false;
    } catch (_) {
      // A failed load must read as an error, not as a $0 balance.
      if (_status.isEmpty) _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _ready =>
      _status['payouts_enabled'] == true ||
      _status['ready'] == true ||
      _status['charges_enabled'] == true;

  num get _available {
    final v = _status['available'] ?? _status['balance'] ?? _status['payout_balance'];
    return v is num ? v : (num.tryParse('$v') ?? 0);
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
        return;
      }
      if (!mounted) return;
      // false/null = embed unavailable → hosted fallback below.
    }
    await _setupHosted();
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

  // Cash-out limits from /payments/config (Stripe-governed); defaults match
  // the platform's published values until the config loads.
  num _fee = 1.99;
  num _min = 5.0;

  Future<void> _loadConfig() async {
    try {
      final cfg = await api.payments.config();
      if (!mounted) return;
      setState(() {
        _fee = cfg['cashout_fee'] is num ? cfg['cashout_fee'] as num : _fee;
        _min = cfg['cashout_min'] is num ? cfg['cashout_min'] as num : _min;
      });
    } catch (_) {/* keep defaults */}
  }

  num? get _entered => num.tryParse(_amount.text.trim());

  /// Whether the payload actually carried a balance (0 may mean "unknown").
  bool get _knowsBalance =>
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
    setState(() => _busy = true);
    try {
      // Stripe rails first (/stripe/payout, supports instant-to-debit-card);
      // the ledger cash-out remains the fallback for backends without it.
      try {
        await api.payments.stripePayout(amount: amount, instant: _instant);
      } on ApiException catch (e) {
        if (e.isNotFound || e.statusCode == 405 || e.statusCode == 501) {
          await api.payments.cashout({'amount': amount});
        } else {
          rethrow;
        }
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
                      // Bank / debit card on file — managed via Stripe's
                      // account-update link (same flow as onboarding).
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.account_balance_outlined,
                              color: scheme.primary),
                          title: const Text('Payout method'),
                          subtitle: const Text(
                              'Change your bank account or debit card'),
                          trailing:
                              Icon(Icons.open_in_new, size: 18,
                                  color: scheme.outline),
                          onTap: _busy
                              ? null
                              : () =>
                                  _setup(component: 'account-management'),
                        ),
                      ),
                      // Debit cards (instant payouts) are added in the Stripe
                      // Express dashboard; connect.stripe.com/express_login
                      // works for every connected account, no backend needed.
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.credit_card_outlined,
                              color: scheme.primary),
                          title: const Text('Add a debit card'),
                          subtitle: const Text(
                              'Instant payouts — sign in to your Stripe '
                              'Express dashboard to add one'),
                          trailing: Icon(Icons.open_in_new,
                              size: 18, color: scheme.outline),
                          onTap: _busy
                              ? null
                              : () => launchUrl(
                                    Uri.parse(
                                        'https://connect.stripe.com/express_login'),
                                    mode: LaunchMode.externalApplication,
                                  ),
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Instant to debit card'),
                        subtitle: const Text(
                            'Minutes instead of 1–2 business days '
                            '(Stripe instant fee applies)'),
                        value: _instant,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _instant = v),
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
      final secret = await _freshSecret();
      if (!mounted) return;
      setState(() {
        _publishableKey = pk;
        _firstSecret = secret;
        _attempt++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = messageFor(e));
    }
  }

  Future<String> _freshSecret() async {
    final s = await api.payments.payoutAccountSession();
    final secret =
        '${s['client_secret'] ?? s['clientSecret'] ?? s['secret'] ?? ''}';
    if (secret.isEmpty) {
      throw StateError(
          'The server returned no account-session client secret');
    }
    return secret;
  }

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
                      component: widget.component,
                      // The session may not have this component enabled;
                      // onboarding is the universal fallback.
                      fallbackComponent: widget.component == 'account-management'
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
