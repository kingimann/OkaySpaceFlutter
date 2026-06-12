import 'package:flutter/material.dart';

import '../core/nfc_pay.dart';
import 'common.dart';
import 'wallet_screen.dart';

const _venmoBlue = Color(0xFF008CFF);

/// NFC tap-to-pay (iOS/Android): tap a pay tag to pay its owner, or write
/// your own pay link to a tag so others can tap to pay you.
///
/// A "pay tag" is any NFC tag carrying an `okayspace://pay?user=…` URI —
/// the same payload as the pay QR, so tags, QRs, and pasted codes are
/// interchangeable.
class TapToPayScreen extends StatefulWidget {
  const TapToPayScreen({super.key});

  @override
  State<TapToPayScreen> createState() => _TapToPayScreenState();
}

class _TapToPayScreenState extends State<TapToPayScreen> {
  late final Future<bool> _available = nfcAvailable();
  bool _changed = false;

  @override
  void dispose() {
    nfcCancel();
    super.dispose();
  }

  /// Shows the "hold your phone near…" waiting sheet (Android has no system
  /// NFC UI; iOS shows its own on top). Returns when dismissed.
  void _showWaiting(String message) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.contactless, size: 64, color: _venmoBlue),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('Keep it still until it vibrates',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    ).whenComplete(nfcCancel);
  }

  void _hideWaiting() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Scans a tag and pays whoever it belongs to.
  Future<void> _tapToPay() async {
    _showWaiting('Hold your phone near the pay tag');
    try {
      final uri = await nfcReadUri();
      _hideWaiting();
      if (!mounted) return;
      final userId = uri?.queryParameters['user'];
      if (uri == null || userId == null || userId.isEmpty) {
        showInfo(context, 'That tag doesn\'t carry OkaySpace pay info.');
        return;
      }
      final recipient = await api.users.publicProfile(userId);
      if (!mounted) return;
      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SendMoneyScreen(
          recipient: recipient,
          initialAmount: uri.queryParameters['amount'],
          initialNote: uri.queryParameters['note'],
        ),
      ));
      if (changed == true) _changed = true;
    } catch (e) {
      _hideWaiting();
      if (mounted) showError(context, e);
    }
  }

  /// Writes the user's pay link to a physical tag.
  Future<void> _writeMyTag() async {
    try {
      final me = await api.auth.me();
      if (!mounted) return;
      _showWaiting('Hold your phone near a writable NFC tag');
      await nfcWriteUri(
          'okayspace://pay?user=${me.userId}&name=${Uri.encodeComponent(me.name)}');
      _hideWaiting();
      if (mounted) showInfo(context, 'Pay tag written — tap it to get paid');
    } catch (e) {
      _hideWaiting();
      if (mounted) showError(context, e);
    }
  }

  Widget _bigAction(
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _venmoBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _venmoBlue, size: 32),
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: const OkayAppBar(title: Text('Tap to pay')),
        body: MaxWidth(
          child: FutureBuilder<bool>(
            future: _available,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data != true) {
                return const CenteredMessage(
                    message:
                        'NFC isn\'t available on this device.\nUse the pay QR instead — it works everywhere.',
                    icon: Icons.contactless_outlined);
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _bigAction(
                    icon: Icons.contactless,
                    title: 'Tap to pay someone',
                    subtitle:
                        'Hold your phone to their pay tag — Send Money opens with them filled in',
                    onTap: _tapToPay,
                  ),
                  const SizedBox(height: 16),
                  _bigAction(
                    icon: Icons.nfc,
                    title: 'Write my pay tag',
                    subtitle:
                        'Save your pay link to an NFC tag or sticker so anyone can tap it to pay you',
                    onTap: _writeMyTag,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Pay tags carry the same link as your pay QR, so either works.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 12)),
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
}
