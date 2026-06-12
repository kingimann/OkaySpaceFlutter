import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  Future<void> _setup() async {
    setState(() => _busy = true);
    try {
      final res = await api.payments.setupPayouts();
      final url = res['url'] ?? res['onboarding_url'] ?? res['account_link'];
      if (!mounted) return;
      if (url != null) {
        Clipboard.setData(ClipboardData(text: '$url'));
        showInfo(context,
            'Onboarding link copied — open it in a browser to finish setup.');
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
      final url = res['url'] ?? res['verification_url'] ?? res['client_secret'];
      if (!mounted) return;
      if (url != null) {
        Clipboard.setData(ClipboardData(text: '$url'));
        showInfo(context, 'Verification link copied — open it to continue.');
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

  /// Flat fee charged per cash-out.
  static const num _fee = 1.99;

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
    if (amount == null || !amount.isFinite || amount < 5) {
      showInfo(context, 'Minimum cash-out is \$5.00.');
      return;
    }
    if (_overAvailable) {
      showInfo(context, 'That\'s more than your available balance.');
      return;
    }
    setState(() => _busy = true);
    try {
      await api.payments.cashout({'amount': amount});
      if (mounted) {
        showInfo(context, 'Cash-out requested');
        _amount.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                                    onPressed: _busy ? null : _setup,
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
                          helperText: (_entered ?? 0) >= 5 && !_overAvailable
                              ? "You'll receive "
                                  '$_symbol${(_entered! - _fee).toStringAsFixed(2)} '
                                  'after the ${_symbol}1.99 fee'
                              : '${_symbol}5 minimum · ${_symbol}1.99 flat fee · instant to debit card',
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
                      const SizedBox(height: 16),
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
