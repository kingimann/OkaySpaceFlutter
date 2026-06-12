import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'support_screen.dart';

/// One area's standing: good, restricted, or suspended/banned.
enum _Standing { good, restricted, blocked }

/// Account standing: lets the user check whether their account is in good
/// standing, overall and per area (General, Marketplace, Messenger), based
/// on the moderation flags the server returns on their own profile.
class AccountStandingScreen extends StatefulWidget {
  const AccountStandingScreen({super.key});

  @override
  State<AccountStandingScreen> createState() => _AccountStandingScreenState();
}

class _AccountStandingScreenState extends State<AccountStandingScreen> {
  late Future<User> _me = api.auth.me();

  Future<void> _reload() async {
    setState(() => _me = api.auth.me());
    try {
      await _me;
    } catch (_) {}
  }

  /// Restriction flags live either flat on the user or under `restrictions`.
  bool _flag(Map<String, dynamic> raw, String key) {
    if (raw[key] == true) return true;
    final r = raw['restrictions'];
    return r is Map && r[key] == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Account standing')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<User>(
            future: _me,
            builder: (context, snap) {
              if (snap.hasError) {
                return CenteredMessage(
                    message: messageFor(snap.error),
                    icon: Icons.error_outline,
                    onRetry: _reload);
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final raw = snap.data!.raw;

              final banned = raw['banned'] == true;
              final suspendedUntil = '${raw['suspended_until'] ?? ''}';
              final suspended =
                  raw['suspended'] == true || suspendedUntil.isNotEmpty;
              final postingOff = _flag(raw, 'posting_disabled');
              final marketOff = _flag(raw, 'marketplace_disabled');
              final messagingOff = _flag(raw, 'messaging_disabled');

              final general = banned
                  ? _Standing.blocked
                  : suspended
                      ? _Standing.blocked
                      : postingOff
                          ? _Standing.restricted
                          : _Standing.good;
              final market =
                  marketOff ? _Standing.restricted : _Standing.good;
              final messenger =
                  messagingOff ? _Standing.restricted : _Standing.good;

              final allGood = general == _Standing.good &&
                  market == _Standing.good &&
                  messenger == _Standing.good;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Overall verdict.
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: allGood
                            ? const [Color(0xFF22C55E), Color(0xFF15803D)]
                            : const [Color(0xFFF59E0B), Color(0xFFB45309)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            allGood
                                ? Icons.verified_user_outlined
                                : Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 34),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  allGood
                                      ? 'Your account is in good standing'
                                      : 'Your account has restrictions',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17)),
                              Text(
                                  allGood
                                      ? 'No restrictions on any part of OkaySpace.'
                                      : 'See the affected areas below.',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _areaCard(
                    icon: Icons.person_outline,
                    title: 'General',
                    standing: general,
                    goodText: 'Account active — posting and full access.',
                    issueText: banned
                        ? 'Your account is banned. Contact support to appeal.'
                        : suspended
                            ? 'Your account is suspended'
                                '${suspendedUntil.isNotEmpty ? ' until ${suspendedUntil.split('T').first}' : ''}.'
                            : 'Posting is currently restricted on your account.',
                  ),
                  _areaCard(
                    icon: Icons.storefront_outlined,
                    title: 'Marketplace',
                    standing: market,
                    goodText: 'You can buy, sell, and message sellers.',
                    issueText:
                        'Marketplace access is currently restricted on your account.',
                  ),
                  _areaCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'Messenger',
                    standing: messenger,
                    goodText: 'You can send and receive messages.',
                    issueText:
                        'Messaging is currently restricted on your account.',
                  ),
                  const SizedBox(height: 16),
                  if (!allGood)
                    FilledButton.icon(
                      icon: const Icon(Icons.support_agent_outlined),
                      label: const Text('Contact support'),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SupportScreen())),
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: scheme.outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Restrictions are placed by moderators for '
                              'community-guideline violations and appear here '
                              'immediately. Pull down to refresh.',
                              style: TextStyle(
                                  color: scheme.outline, fontSize: 12)),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _areaCard({
    required IconData icon,
    required String title,
    required _Standing standing,
    required String goodText,
    required String issueText,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (standing) {
      _Standing.good => (const Color(0xFF22C55E), 'Good'),
      _Standing.restricted => (const Color(0xFFF59E0B), 'Restricted'),
      _Standing.blocked => (scheme.error, 'Suspended'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: standing == _Standing.good
            ? null
            : Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                Text(standing == _Standing.good ? goodText : issueText,
                    style: TextStyle(color: scheme.outline, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
