import 'package:flutter/material.dart';

import 'common.dart';

/// Client-side money guards: catch mistakes and casual abuse before a
/// request leaves the device. Real enforcement (velocity limits, balance
/// atomicity, replay protection) lives server-side — these are the seat
/// belts, not the vault door.

/// Per-transaction caps (advisory; the server owns the real limits).
const kMaxTopUp = 50;
const kMaxSend = 2000;
const kMaxRequest = 2000;

/// Parses a user-typed amount: cents precision, finite, positive.
/// Returns null for anything that shouldn't reach a money endpoint.
num? parseMoney(String raw) {
  final v = num.tryParse(raw.trim().replaceAll(',', ''));
  if (v == null || !v.isFinite || v <= 0) return null;
  // More than 2 decimals is either a typo or someone probing for
  // rounding bugs — normalize to cents.
  return (v * 100).round() / 100;
}

/// Human message when [amount] violates min/max, else null.
String? amountIssue(num amount,
    {num min = 0.01, required num max, String what = 'amount'}) {
  if (amount < min) {
    return 'The minimum $what is \$${min.toStringAsFixed(2)}.';
  }
  if (amount > max) {
    return 'The maximum $what is \$${max.toStringAsFixed(0)} per '
        'transaction.';
  }
  return null;
}

// --- Duplicate-action guard ------------------------------------------------

final Map<String, DateTime> _recentActions = {};

/// True when the same money action (key = kind+target+amount) ran in the
/// last [window] — a double-tap, a retry after a slow network, or a repeat
/// the user probably didn't intend.
bool isRecentDuplicate(String key,
    {Duration window = const Duration(seconds: 45)}) {
  final at = _recentActions[key];
  return at != null && DateTime.now().difference(at) < window;
}

void markMoneyAction(String key) {
  _recentActions[key] = DateTime.now();
  // Keep the map tiny.
  if (_recentActions.length > 32) {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    _recentActions.removeWhere((_, t) => t.isBefore(cutoff));
  }
}

/// Confirms a duplicate money action with the user.
Future<bool> confirmDuplicate(BuildContext context, String what) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Send again?'),
      content: Text('You just did this — $what. Do it again?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, repeat it')),
      ],
    ),
  );
  return go == true;
}

// --- Large-amount confirmation ----------------------------------------------

/// For amounts at/over [threshold], requires the user to type the whole
/// dollar figure — stops fat-fingered extra zeros cold.
Future<bool> confirmLargeAmount(BuildContext context, num amount,
    {num threshold = 250}) async {
  if (amount < threshold) return true;
  final whole = amount.floor().toString();
  final ctrl = TextEditingController();
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Large amount — confirm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This is \$${amount.toStringAsFixed(2)}. '
                  'Type $whole to continue.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setDialog(() {}),
                decoration: InputDecoration(
                    hintText: whole, border: const OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: ctrl.text.trim() == whole
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Confirm')),
          ],
        ),
      ),
    );
    return ok == true;
  } finally {
    ctrl.dispose();
  }
}

/// Blocks paying/requesting yourself.
bool isSelf(String? userId) =>
    userId != null && currentUserId != null && userId == currentUserId;
