import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'wallet_screen.dart';

/// The current user's branded pay QR plus a "pay someone" code entry.
///
/// The QR encodes `okayspace://pay?user=<id>` — another OkaySpace app scans
/// (or pastes) it and lands in Send Money with the recipient preselected.
class PayQrScreen extends StatefulWidget {
  const PayQrScreen({super.key});

  @override
  State<PayQrScreen> createState() => _PayQrScreenState();
}

class _PayQrScreenState extends State<PayQrScreen> {
  late final Future<User> _me = api.auth.me();

  String _payload(User u) =>
      'okayspace://pay?user=${u.userId}&name=${Uri.encodeComponent(u.name)}';

  /// Parses a pay code/link and opens Send Money for that user.
  Future<void> _paySomeone() async {
    final code = await promptText(context,
        title: 'Pay someone',
        hint: 'Paste their pay code or @username',
        action: 'Continue');
    if (code == null) return;
    String? userId;
    final trimmed = code.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters['user'] != null) {
      userId = uri.queryParameters['user'];
    }
    try {
      PublicUser? recipient;
      if (userId != null && userId.isNotEmpty) {
        recipient = await api.users.publicProfile(userId);
      } else {
        // Fall back to a username/name search.
        final results =
            await api.users.search(trimmed.replaceFirst('@', ''));
        if (results.isNotEmpty) recipient = results.first;
      }
      if (!mounted) return;
      if (recipient == null) {
        showInfo(context, 'No matching user found.');
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SendMoneyScreen(recipient: recipient)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Pay by QR')),
      body: MaxWidth(
        child: FutureBuilder<User>(
          future: _me,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final u = snap.data!;
            final data = _payload(u);
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Branded QR card.
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, darken(scheme.primary, 0.22)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      Avatar(url: u.picture, name: u.name, radius: 30),
                      const SizedBox(height: 8),
                      Text(u.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      Text(u.handle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8))),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: data,
                          size: 220,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Scan to pay me on OkaySpace',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: data));
                    showInfo(context, 'Pay code copied');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy my pay code'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _paySomeone,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Pay someone'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
