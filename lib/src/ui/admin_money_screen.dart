import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_settings_screen.dart';
import 'common.dart';

List<Map<String, dynamic>> _asMapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ?? data['items'] ?? data['badges'] ?? data['results'];
  }
  if (list is List) {
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

num _n(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

String _usd(dynamic v) => '\$${_n(v).toStringAsFixed(2)}';

/// Admin · Payments & data: Stripe mode, platform switches, fees, revenue,
/// and the destructive resets.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  bool? _testPayments;
  bool? _mobileOnly;
  bool? _mobileWebGate;
  String _regMode = 'open';

  Future<void> _generateInvites() async {
    try {
      final res = await api.admin.createInvites(count: 5);
      final codes = res['codes'] ?? res['invites'] ?? res['data'];
      if (!mounted) return;
      final list = codes is List
          ? codes.map((c) => c is Map ? '${c['code'] ?? c}' : '$c').toList()
          : <String>[];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Invite codes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (list.isEmpty)
                const Text('Created — check the invites list.')
              else
                for (final c in list)
                  SelectableText(c,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 15)),
            ],
          ),
          actions: [
            if (list.isNotEmpty)
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: list.join('\n')));
                  Navigator.pop(dialogContext);
                  if (mounted) showInfo(context, 'Codes copied');
                },
                child: const Text('Copy all'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
  String _stripeStatus = '';
  String _webBuild = '';
  Map<String, dynamic> _revenue = const {};
  final _feePercent = TextEditingController();
  final _feeCents = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feePercent.dispose();
    _feeCents.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        api.admin.testPayments().catchError((_) => null),
        api.admin.mobileOnly().catchError((_) => null),
        api.admin.webBuild().catchError((_) => null),
        api.admin.revenue().catchError((_) => null),
        api.admin.fees().catchError((_) => null),
        api.admin.mobileWebGate().catchError((_) => null),
        api.admin.registrationMode().catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        final rm = results[6];
        if (rm is Map) {
          final m = '${rm['mode'] ?? 'open'}'.toLowerCase();
          if (const ['open', 'invite', 'closed'].contains(m)) _regMode = m;
        }
        final tp = results[0];
        if (tp is Map) {
          _testPayments = tp['enabled'] == true || tp['test'] == true;
          _stripeStatus = '${tp['status'] ?? (tp['configured'] == false ? 'not configured' : '')}';
        }
        final mo = results[1];
        if (mo is Map) _mobileOnly = mo['enabled'] == true;
        final mwg = results[5];
        if (mwg is Map) _mobileWebGate = mwg['enabled'] == true;
        final wb = results[2];
        if (wb is Map) _webBuild = '${wb['build'] ?? wb['token'] ?? ''}';
        final rev = results[3];
        if (rev is Map) _revenue = Map<String, dynamic>.from(rev);
        final fees = results[4];
        if (fees is Map) {
          _feePercent.text = '${fees['platform_fee_percent'] ?? ''}';
          _feeCents.text = '${fees['transaction_fee_cents'] ?? ''}';
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() op, String ok) async {
    try {
      await op();
      if (mounted) {
        showInfo(context, ok);
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = num.tryParse(_feePercent.text.trim()) ?? 0;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Payments & data')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : MaxWidth(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      title: const Text('Test payments'),
                      subtitle: Text(_stripeStatus.isEmpty
                          ? 'Stripe test mode on/off'
                          : 'Stripe: $_stripeStatus'),
                      value: _testPayments ?? false,
                      onChanged: (v) => _run(
                          () => api.admin.setTestPayments(v),
                          v ? 'Test payments on' : 'Live payments on'),
                    ),
                    SwitchListTile(
                      title: const Text('Mobile only (PC gate)'),
                      subtitle: const Text(
                          'Desktop browsers get the "open on your phone" screen'),
                      value: _mobileOnly ?? false,
                      onChanged: (v) => _run(() => api.admin.setMobileOnly(v),
                          v ? 'PC gate on' : 'PC gate off'),
                    ),
                    SwitchListTile(
                      title: const Text('Mobile web gate'),
                      subtitle: const Text(
                          'Phone browsers see a "Get the app" banner '
                          '(needs store links configured in the build)'),
                      value: _mobileWebGate ?? false,
                      onChanged: (v) => _run(
                          () => api.admin.setMobileWebGate(v),
                          v ? 'Mobile web gate on' : 'Mobile web gate off'),
                    ),
                    // Registration mode: open / invite-only / closed.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('REGISTRATION',
                          style: TextStyle(
                              color: scheme.outline,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final (id, label) in const [
                            ('open', 'Open'),
                            ('invite', 'Invite only'),
                            ('closed', 'Closed'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _regMode == id,
                              onSelected: (_) => _run(() async {
                                await api.admin.setRegistrationMode(id);
                                if (mounted) setState(() => _regMode = id);
                              }, 'Registration: $label'),
                            ),
                        ],
                      ),
                    ),
                    if (_regMode == 'invite')
                      ListTile(
                        leading: Icon(Icons.confirmation_number_outlined,
                            color: scheme.primary),
                        title: const Text('Generate invite codes'),
                        subtitle: const Text('Create codes to share'),
                        onTap: _generateInvites,
                      ),
                    ListTile(
                      leading: Icon(Icons.refresh, color: scheme.primary),
                      title: const Text('Force web update'),
                      subtitle: Text(_webBuild.isEmpty
                          ? 'Reload open browser tabs to the latest deploy'
                          : 'Current build: $_webBuild'),
                      onTap: () async {
                        if (await adminConfirm(
                            context,
                            'Force web update',
                            'Open browser tabs will clear cache and reload '
                                'within minutes. Mobile apps are unaffected.')) {
                          await _run(
                              api.admin.bumpWebBuild, 'Web build bumped');
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    // Platform revenue.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Platform revenue',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(_usd(_revenue['total_fees'] ??
                                    _revenue['total']),
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            for (final (label, key) in const [
                              ('Transfer & send fees', 'send_fees'),
                              ('Cash-out fees', 'cashout_fees'),
                              ('Paid to creators', 'paid_to_creators'),
                              ('Fee-paying events', 'fee_events'),
                            ])
                              if (_revenue[key] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                          child: Text(label,
                                              style: TextStyle(
                                                  color: scheme.outline,
                                                  fontSize: 13))),
                                      Text(
                                          key == 'fee_events'
                                              ? '${_n(_revenue[key]).toInt()}'
                                              : _usd(_revenue[key]),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Fees editor.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Fees & revenue split',
                                style:
                                    TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _feePercent,
                                    keyboardType: const TextInputType
                                        .numberWithOptions(decimal: true),
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                        labelText: 'Platform cut %',
                                        border: OutlineInputBorder()),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _feeCents,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Per-transaction ¢',
                                        border: OutlineInputBorder()),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                                'Creators keep ${(100 - pct).clamp(0, 100)}% · you keep ${pct.clamp(0, 100)}%',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 12)),
                            const SizedBox(height: 10),
                            FilledButton(
                              onPressed: () => _run(
                                  () => api.admin.setFees({
                                        'platform_fee_percent': num.tryParse(
                                                _feePercent.text.trim()) ??
                                            0,
                                        'transaction_fee_cents':
                                            int.tryParse(
                                                    _feeCents.text.trim()) ??
                                                0,
                                      }),
                                  'Fees saved'),
                              child: const Text('Save fees'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error)),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Reset money'),
                      onPressed: () async {
                        if (await adminConfirm(
                            context,
                            'Reset money',
                            'Wipes ALL wallets, tips, subscriptions, payouts, '
                                'transfers, and ad balances. This cannot be undone.',
                            action: 'Reset money',
                            destructive: true)) {
                          await _run(api.admin.resetMoney, 'Money reset');
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(color: scheme.error)),
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Reset analytics'),
                      onPressed: () async {
                        if (await adminConfirm(
                            context,
                            'Reset analytics',
                            'Wipes impressions, clicks, spend, and views. '
                                'This cannot be undone.',
                            action: 'Reset analytics',
                            destructive: true)) {
                          await _run(
                              api.admin.resetAnalytics, 'Analytics reset');
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Admin · Ad revenue: read-only ad dashboard with top earners/advertisers.
class AdminRevenueScreen extends StatefulWidget {
  const AdminRevenueScreen({super.key});

  @override
  State<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends State<AdminRevenueScreen> {
  late Future<Map<String, dynamic>> _data = _fetch();

  Future<Map<String, dynamic>> _fetch() async {
    final d = await api.admin.adRevenue();
    return d is Map ? Map<String, dynamic>.from(d) : const {};
  }

  Future<void> _reload() async {
    setState(() => _data = _fetch());
    try {
      await _data;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Ad revenue')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _data,
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
              final d = snapshot.data ?? const {};
              final impressions = _n(d['impressions']);
              final clicks = _n(d['clicks']);
              final ctr = impressions > 0
                  ? (clicks / impressions * 100).toStringAsFixed(1)
                  : '0.0';
              final earners = _asMapList(d['top_earners']);
              final advertisers = _asMapList(d['top_advertisers']);

              Widget stat(String label, String value) => Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 11)),
                            Text(value,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ],
                        ),
                      ),
                    ),
                  );

              Widget ranked(String title, List<Map<String, dynamic>> rows,
                      String amountKey) =>
                  rows.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            for (var i = 0; i < rows.length; i++)
                              ListTile(
                                dense: true,
                                leading: Text('#${i + 1}',
                                    style: TextStyle(
                                        color: scheme.outline,
                                        fontWeight: FontWeight.bold)),
                                title: Text(
                                    '${rows[i]['name'] ?? rows[i]['user_name'] ?? 'User'}'),
                                trailing: Text(_usd(rows[i][amountKey] ??
                                    rows[i]['amount'] ??
                                    rows[i]['total'])),
                              ),
                          ],
                        );

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Platform cut',
                              style: TextStyle(
                                  color: scheme.outline, fontSize: 12)),
                          Text(_usd(d['platform_cut'] ?? d['platform_revenue']),
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                              'Total spend ${_usd(d['total_spend'] ?? d['spend'])} · paid to creators ${_usd(d['creator_payouts'] ?? d['paid_to_creators'])}',
                              style: TextStyle(
                                  color: scheme.outline, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    stat('Impressions', '${impressions.toInt()}'),
                    const SizedBox(width: 8),
                    stat('Clicks', '${clicks.toInt()}'),
                    const SizedBox(width: 8),
                    stat('CTR', '$ctr%'),
                  ]),
                  Row(children: [
                    stat('Active campaigns',
                        '${_n(d['active_campaigns']).toInt()}'),
                    const SizedBox(width: 8),
                    stat('Creator payouts',
                        _usd(d['creator_payouts'] ?? d['paid_to_creators'])),
                  ]),
                  ranked('Top earners', earners, 'earned'),
                  ranked('Top advertisers', advertisers, 'spent'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Admin · Custom badges: create/delete the badges assignable in Manage users.
class AdminBadgesScreen extends StatefulWidget {
  const AdminBadgesScreen({super.key});

  @override
  State<AdminBadgesScreen> createState() => _AdminBadgesScreenState();
}

class _AdminBadgesScreenState extends State<AdminBadgesScreen> {
  late Future<List<Map<String, dynamic>>> _badges = _fetch();
  final _label = TextEditingController();
  final _icon = TextEditingController();
  Color _color = const Color(0xFF3B82F6);
  bool _busy = false;

  static const _swatches = [
    Color(0xFF3B82F6), Color(0xFF22C55E), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFFEC4899),
    Color(0xFF06B6D4), Color(0xFF64748B),
  ];

  Future<List<Map<String, dynamic>>> _fetch() =>
      api.admin.listBadges().then((d) => _asMapList(d, 'badges'));

  void _reload() => setState(() => _badges = _fetch());

  @override
  void dispose() {
    _label.dispose();
    _icon.dispose();
    super.dispose();
  }

  String get _hex =>
      '#${(_color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _create() async {
    final label = _label.text.trim();
    final icon = _icon.text.trim();
    if (label.isEmpty || icon.isEmpty) {
      showInfo(context, 'A label and an icon are required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await api.admin
          .createBadge({'label': label, 'icon': icon, 'color': _hex});
      if (mounted) {
        showInfo(context, 'Badge created');
        _label.clear();
        _icon.clear();
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id, String label) async {
    if (!await adminConfirm(context, 'Delete "$label"',
        'Removes this badge from everyone who has it.',
        action: 'Delete', destructive: true)) {
      return;
    }
    if (!mounted) return;
    try {
      await api.admin.deleteBadge(id);
      if (mounted) {
        showInfo(context, 'Badge deleted');
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
      appBar: const OkayAppBar(title: Text('Admin · Custom badges')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New badge',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _label,
                      maxLength: 40,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Label',
                          counterText: '',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _icon,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Icon (emoji or image URL)',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final c in _swatches)
                          InkWell(
                            onTap: () => setState(() => _color = c),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: _color == c
                                    ? Border.all(
                                        color: scheme.onSurface, width: 2.5)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Live preview chip.
                    if (_label.text.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _color.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_icon.text.trim().isEmpty
                                ? '🏅'
                                : _icon.text.trim()),
                            const SizedBox(width: 5),
                            Text(_label.text.trim(),
                                style: TextStyle(
                                    color: _color,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Create badge'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('All badges',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            AsyncList<Map<String, dynamic>>(
              future: _badges,
              emptyMessage: 'No custom badges yet.',
              emptyIcon: Icons.military_tech_outlined,
              builder: (context, badges) => Column(
                children: [
                  for (final b in badges)
                    ListTile(
                      leading: Text('${b['icon'] ?? '🏅'}',
                          style: const TextStyle(fontSize: 22)),
                      title: Text('${b['label'] ?? b['name'] ?? 'Badge'}'),
                      trailing: IconButton(
                        icon:
                            Icon(Icons.delete_outline, color: scheme.error),
                        onPressed: () => _delete(
                            '${b['id'] ?? b['badge_id']}',
                            '${b['label'] ?? b['name'] ?? 'Badge'}'),
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
}
