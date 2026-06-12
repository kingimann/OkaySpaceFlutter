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

/// Admin settings hub: every staff tool, grouped by area. Admins see all
/// groups; mods see only the Staff group. The backend enforces roles
/// server-side regardless of what's shown here.
class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key, required this.user});

  final User user;

  bool get _isAdmin => user.role == 'admin';
  bool get _isStaff => _isAdmin || user.role == 'mod';

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
        child: ListView(
          children: [
            if (_isAdmin) ...[
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
    );
  }
}
