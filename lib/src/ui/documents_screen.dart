import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'settings_screen.dart';

/// Verification hub (§11): shows email / phone / ID verification status and a
/// link to manage them in Account settings.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  Future<User> _me = api.auth.me();

  Future<void> _reload() async {
    setState(() => _me = api.auth.me());
    await _me;
  }

  Widget _row(IconData icon, String title, String subtitle, bool done,
      {VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    final color = done ? const Color(0xFF22C55E) : scheme.outline;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(done ? Icons.check_circle : Icons.schedule,
                size: 14, color: color),
            const SizedBox(width: 4),
            Text(done ? 'Verified' : 'Pending',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Verification')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<User>(
          future: _me,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return CenteredMessage(
                  message: messageFor(snap.error),
                  icon: Icons.error_outline,
                  onRetry: _reload);
            }
            final u = snap.data!;
            final done = [
              u.emailVerified,
              u.phoneVerified,
              u.idVerified
            ].where((v) => v).length;
            void openAccount() => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => SettingsScreen(user: u)))
                .then((_) => _reload());
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          u.verified
                              ? Icons.verified
                              : Icons.shield_outlined,
                          color: scheme.primary,
                          size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                u.verified
                                    ? 'Verified account'
                                    : '$done of 3 verifications complete',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                                'Verify your identity to unlock payouts and a verified badge.',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 12.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _row(Icons.mark_email_read_outlined, 'Email',
                    done > 0 ? u.email : 'Add and verify your email',
                    u.emailVerified,
                    onTap: openAccount),
                _row(Icons.phone_android, 'Phone number',
                    'Verify your phone for added security', u.phoneVerified,
                    onTap: openAccount),
                _row(Icons.badge_outlined, 'Government ID',
                    'Verify your identity for payouts', u.idVerified,
                    onTap: openAccount),
              ],
            );
          },
        ),
      ),
    );
  }
}
