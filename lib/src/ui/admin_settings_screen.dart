import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'admin_money_screen.dart';
import 'admin_staff_screen.dart';
import 'admin_system_screen.dart';
import 'admin_users_screen.dart';
import 'common.dart';

/// Confirms a destructive/admin action; returns true when accepted.
Future<bool> adminConfirm(BuildContext context, String title, String message,
    {String action = 'Confirm', bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Quick stats strip on the hub: revenue, open tickets, pending roadside
/// verifications. Each value is best-effort — failures render as '—'.
class _HubStats extends StatefulWidget {
  const _HubStats({super.key});

  @override
  State<_HubStats> createState() => _HubStatsState();
}

class _HubStatsState extends State<_HubStats> {
  String _revenue = '…';
  String _tickets = '…';
  String _verifications = '…';

  @override
  void initState() {
    super.initState();
    num n(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
    int count(dynamic d, String key) {
      dynamic list = d;
      if (d is Map) list = d[key] ?? d['items'] ?? d['results'];
      return list is List ? list.length : 0;
    }

    api.admin.revenue().then((d) {
      if (mounted && d is Map) {
        setState(() => _revenue =
            '\$${n(d['total_fees'] ?? d['total']).toStringAsFixed(0)}');
      }
    }).catchError((_) {
      if (mounted) setState(() => _revenue = '—');
    });
    api.admin.supportTickets(status: 'open').then((d) {
      if (mounted) setState(() => _tickets = '${count(d, 'tickets')}');
    }).catchError((_) {
      if (mounted) setState(() => _tickets = '—');
    });
    api.admin.roadsideVerifications().then((d) {
      if (mounted) {
        setState(() => _verifications = '${count(d, 'verifications')}');
      }
    }).catchError((_) {
      if (mounted) setState(() => _verifications = '—');
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget stat(IconData icon, String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(label,
                    style: TextStyle(color: scheme.outline, fontSize: 11)),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          stat(Icons.payments_outlined, 'Platform fees', _revenue),
          const SizedBox(width: 10),
          stat(Icons.support_agent_outlined, 'Open tickets', _tickets),
          const SizedBox(width: 10),
          stat(Icons.fact_check_outlined, 'Verifications', _verifications),
        ],
      ),
    );
  }
}

/// Admin settings hub: every staff tool, grouped by area. Admins see all
/// groups; mods see only the Staff group. The backend enforces roles
/// server-side regardless of what's shown here.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key, required this.user});

  final User user;

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  /// Bumped on pull-to-refresh to re-create the stats strip.
  int _statsGen = 0;

  bool get _isAdmin => widget.user.role == 'admin';
  bool get _isStaff => _isAdmin || widget.user.role == 'mod';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_isStaff) {
      return const Scaffold(
        appBar: OkayAppBar(title: Text('Admin settings')),
        body: CenteredMessage(
            message: 'Admins only.', icon: Icons.lock_outline),
      );
    }

    Widget group(String title, List<(IconData, String, String, Widget)> rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    color: scheme.outline,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6)),
          ),
          for (final (icon, label, sub, screen) in rows)
            ListTile(
              leading: Icon(icon, color: scheme.primary),
              title: Text(label),
              subtitle: Text(sub,
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: scheme.outline),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => screen)),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin settings')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _statsGen++);
            // Hold the indicator briefly while the recreated stats load.
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_isAdmin) ...[
              _HubStats(key: ValueKey(_statsGen)),
              group('Moderation', [
                (
                  Icons.manage_accounts_outlined,
                  'Manage users',
                  'Search, verify, roles, bans, wallets, badges',
                  const AdminUsersScreen()
                ),
                (
                  Icons.history,
                  'Audit log',
                  'Every admin action, newest first',
                  const AdminAuditScreen()
                ),
              ]),
              group('Money & growth', [
                (
                  Icons.payments_outlined,
                  'Payments & data',
                  'Stripe mode, fees, revenue, resets',
                  const AdminPaymentsScreen()
                ),
                (
                  Icons.campaign_outlined,
                  'Ad revenue',
                  'Spend, CTR, top earners & advertisers',
                  const AdminRevenueScreen()
                ),
                (
                  Icons.military_tech_outlined,
                  'Custom badges',
                  'Create the badges you can pin to users',
                  const AdminBadgesScreen()
                ),
              ]),
              group('System', [
                (
                  Icons.smart_toy_outlined,
                  'Test bot',
                  'Simulate ad traffic to verify money flow',
                  const AdminBotScreen()
                ),
                (
                  Icons.extension_outlined,
                  'Integrations & SDKs',
                  'Health of every backend integration',
                  const AdminIntegrationsScreen()
                ),
                (
                  Icons.cloud_outlined,
                  'Render hosting',
                  'Deploy, restart, env vars',
                  const AdminRenderScreen()
                ),
              ]),
            ],
            group('Staff', [
              (
                Icons.car_repair_outlined,
                'Roadside verifications',
                'Review insurance & ownership documents',
                AdminRoadsideScreen(isAdmin: _isAdmin)
              ),
              (
                Icons.support_agent_outlined,
                'Support queue',
                'Open tickets across the platform',
                const AdminSupportScreen()
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
        ),
      ),
    );
  }
}
