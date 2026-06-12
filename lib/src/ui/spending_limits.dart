import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Self-imposed wallet spending limits, kept on-device: an optional cap per
/// day, week (Monday-based), and month. Spend-to-date is computed from the
/// wallet's outgoing transactions; Send Money warns before crossing a cap.
class SpendingLimits extends ChangeNotifier {
  SpendingLimits._() {
    _load();
  }

  static final SpendingLimits instance = SpendingLimits._();

  static const _key = 'okayspace.wallet_limits';
  static const _storage = FlutterSecureStorage();

  num? _daily;
  num? _weekly;
  num? _monthly;
  bool _loaded = false;

  num? get daily => _daily;
  num? get weekly => _weekly;
  num? get monthly => _monthly;
  bool get isLoaded => _loaded;

  /// Whether any limit is configured.
  bool get any => _daily != null || _weekly != null || _monthly != null;

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw);
        if (m is Map) {
          _daily = m['daily'] is num ? m['daily'] as num : null;
          _weekly = m['weekly'] is num ? m['weekly'] as num : null;
          _monthly = m['monthly'] is num ? m['monthly'] as num : null;
        }
      }
    } catch (_) {/* start fresh */}
    _loaded = true;
    notifyListeners();
  }

  Future<void> set({num? daily, num? weekly, num? monthly}) async {
    _daily = daily;
    _weekly = weekly;
    _monthly = monthly;
    notifyListeners();
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          if (_daily != null) 'daily': _daily,
          if (_weekly != null) 'weekly': _weekly,
          if (_monthly != null) 'monthly': _monthly,
        }),
      );
    } catch (_) {/* best effort */}
  }

  /// Outgoing spend since [since], from a wallet transaction list.
  static num _spentSince(List<WalletTxn> txns, DateTime since) => txns
      .where((t) =>
          t.amount < 0 && t.createdAt != null && !t.createdAt!.isBefore(since))
      .fold<num>(0, (a, t) => a + t.amount.abs());

  static DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _weekStart() {
    final now = DateTime.now();
    // Date arithmetic (not Duration) so DST transitions can't shift the day.
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  static DateTime _monthStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  /// Spend-to-date per period: (label, limit, spent) for each configured cap.
  List<({String label, num limit, num spent})> usage(List<WalletTxn> txns) =>
      [
        if (_daily != null)
          (
            label: 'Today',
            limit: _daily!,
            spent: _spentSince(txns, _todayStart())
          ),
        if (_weekly != null)
          (
            label: 'This week',
            limit: _weekly!,
            spent: _spentSince(txns, _weekStart())
          ),
        if (_monthly != null)
          (
            label: 'This month',
            limit: _monthly!,
            spent: _spentSince(txns, _monthStart())
          ),
      ];

  /// The first limit that [amount] more spending would cross, or null when
  /// the send fits inside every configured cap.
  ({String label, num limit, num spent})? wouldExceed(
      List<WalletTxn> txns, num amount) {
    for (final u in usage(txns)) {
      if (u.spent + amount > u.limit) return u;
    }
    return null;
  }
}

/// Convenience accessor.
final spendingLimits = SpendingLimits.instance;

/// Overview card: progress per configured limit, or a set-up prompt. Tapping
/// the tune icon (or the prompt) opens the limits editor.
class SpendingLimitsCard extends StatelessWidget {
  const SpendingLimitsCard(
      {super.key,
      required this.txns,
      required this.currency,
      this.hideAmounts = false});

  final List<WalletTxn> txns;
  final String currency;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: spendingLimits,
      builder: (context, _) {
        if (!spendingLimits.isLoaded) return const SizedBox.shrink();

        if (!spendingLimits.any) {
          return Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showSpendingLimitsEditor(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.speed_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Set daily, weekly & monthly limits',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right, color: scheme.outline),
                  ],
                ),
              ),
            ),
          );
        }

        final rows = spendingLimits.usage(txns);
        final anyOver = rows.any((u) => u.spent > u.limit);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: anyOver ? Border.all(color: scheme.error) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.speed_outlined,
                      size: 20,
                      color: anyOver ? scheme.error : scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Spending limits',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  InkWell(
                    onTap: () => showSpendingLimitsEditor(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child:
                          Icon(Icons.tune, size: 18, color: scheme.outline),
                    ),
                  ),
                ],
              ),
              for (final u in rows) ...[
                const SizedBox(height: 10),
                _limitRow(context, u),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _limitRow(
      BuildContext context, ({String label, num limit, num spent}) u) {
    final scheme = Theme.of(context).colorScheme;
    final frac = u.limit > 0 ? (u.spent / u.limit).clamp(0.0, 1.0) : 0.0;
    final over = u.spent > u.limit;
    final near = !over && u.spent >= u.limit * 0.8;
    final color = over
        ? scheme.error
        : near
            ? const Color(0xFFF59E0B)
            : scheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(u.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Text(
              hideAmounts
                  ? '••••'
                  : '${formatMoney(u.spent, currency)} / ${formatMoney(u.limit, currency)}',
              style: TextStyle(
                  color: over ? scheme.error : scheme.outline, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 7,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Bottom-sheet editor: one amount field per period; blank disables that cap.
Future<void> showSpendingLimitsEditor(BuildContext context) async {
  final daily = TextEditingController(
      text: spendingLimits.daily?.toStringAsFixed(0) ?? '');
  final weekly = TextEditingController(
      text: spendingLimits.weekly?.toStringAsFixed(0) ?? '');
  final monthly = TextEditingController(
      text: spendingLimits.monthly?.toStringAsFixed(0) ?? '');

  num? parse(TextEditingController c) {
    final v = num.tryParse(c.text.trim());
    return v != null && v > 0 ? v : null;
  }

  try {
    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Spending limits',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Leave a field blank for no limit.',
                  style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.outline,
                      fontSize: 13)),
              const SizedBox(height: 16),
              for (final (label, c) in [
                ('Daily limit', daily),
                ('Weekly limit', weekly),
                ('Monthly limit', monthly),
              ]) ...[
                TextField(
                  controller: c,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: label,
                      prefixIcon: const Icon(Icons.attach_money),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Save limits'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (save == true) {
      await spendingLimits.set(
          daily: parse(daily), weekly: parse(weekly), monthly: parse(monthly));
    }
  } finally {
    daily.dispose();
    weekly.dispose();
    monthly.dispose();
  }
}
