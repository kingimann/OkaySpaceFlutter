import 'package:flutter/material.dart';

import 'common.dart';

/// Admin · reconcile a user's wallet against their real Stripe payments.
///
/// Enter the email a user paid with; this shows their actual Stripe charges and
/// the verified net (deposited − refunded). Optionally set that user's wallet
/// balance to the verified amount. It only ever shows/uses real Stripe data.
class AdminStripeReconcileScreen extends StatefulWidget {
  const AdminStripeReconcileScreen({super.key});

  @override
  State<AdminStripeReconcileScreen> createState() =>
      _AdminStripeReconcileScreenState();
}

class _AdminStripeReconcileScreenState
    extends State<AdminStripeReconcileScreen> {
  final _email = TextEditingController();
  final _amount = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result;

  double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> _list(Object? v) =>
      (v is List ? v : const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

  Future<void> _lookup() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final res = await api.admin.stripeLookup(email);
      if (!mounted) return;
      final totals = _list(res['totals']);
      final net = totals.isEmpty ? 0.0 : _num(totals.first['net']);
      setState(() {
        _result = res;
        _amount.text = net.toStringAsFixed(2);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reconcile() async {
    final res = _result;
    if (res == null) return;
    final user = res['user'] is Map ? (res['user'] as Map) : null;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null) {
      showInfo(context, 'Enter a valid amount');
      return;
    }
    final target = user?['username'] ?? user?['email'] ?? _email.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set wallet balance'),
        content: Text(
            'Set $target\'s wallet balance to \$${amount.toStringAsFixed(2)}?\n\n'
            'This is real money. It reflects Stripe deposits, not in-app '
            'spending — only set it if little or nothing was spent in-app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Set balance')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      final r = await api.admin.stripeReconcile(
        userId: user?['user_id'] as String?,
        email: user == null ? _email.text.trim() : null,
        amount: amount,
      );
      if (!mounted) return;
      showInfo(context,
          'Wallet set to \$${_num(r['wallet_balance']).toStringAsFixed(2)}');
      await _lookup(); // refresh the displayed current balance
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final res = _result;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Stripe reconcile')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email used on Stripe',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _loading ? null : _lookup,
                ),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 8),
            Text(
              'Shows real Stripe payments for this email. Net = deposited − '
              'refunded (it does not subtract in-app spending).',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (res != null && res['configured'] == false)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('Stripe isn\'t configured on the backend '
                    '(STRIPE_SECRET_KEY is not set).'),
              ),
            if (res != null && res['configured'] != false) ...[
              const SizedBox(height: 16),
              _totalsCard(scheme, _list(res['totals'])),
              const SizedBox(height: 12),
              _userCard(scheme, res['user'] is Map ? res['user'] as Map : null),
              const SizedBox(height: 12),
              _paymentsCard(scheme, _list(res['payments'])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _totalsCard(ColorScheme scheme, List<Map<String, dynamic>> totals) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verified Stripe total',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (totals.isEmpty)
              Text('No Stripe payments found for this email.',
                  style: TextStyle(color: scheme.onSurfaceVariant))
            else
              for (final t in totals)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${t['currency']}  net \$${_num(t['net']).toStringAsFixed(2)}'
                    '   (in \$${_num(t['gross']).toStringAsFixed(2)} · '
                    'refunded \$${_num(t['refunded']).toStringAsFixed(2)})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _userCard(ColorScheme scheme, Map? user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Matching account',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (user == null)
              Text(
                'No app account found with this email in the current database. '
                'You can still set a balance by email below if one exists.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else ...[
              Text('@${user['username'] ?? '?'}  ·  ${user['email'] ?? ''}'),
              const SizedBox(height: 4),
              Text(
                'Current wallet: \$${_num(user['wallet_balance']).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Set wallet to',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _reconcile,
                child: const Text('Set balance'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _paymentsCard(ColorScheme scheme, List<Map<String, dynamic>> payments) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payments (${payments.length})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (payments.isEmpty)
              Text('None.', style: TextStyle(color: scheme.onSurfaceVariant))
            else
              for (final p in payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${p['currency']} \$${_num(p['amount']).toStringAsFixed(2)}'
                              '${_num(p['refunded']) > 0 ? '  (refunded \$${_num(p['refunded']).toStringAsFixed(2)})' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if ('${p['description'] ?? ''}'.isNotEmpty)
                              Text('${p['description']}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
                            Text(_when(p['created']),
                                style: TextStyle(
                                    fontSize: 11, color: scheme.outline)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _when(Object? unixSeconds) {
    final s = unixSeconds is num ? unixSeconds.toInt() : 0;
    if (s == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(s * 1000).toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
