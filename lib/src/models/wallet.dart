import 'json.dart';

/// A single wallet transaction.
class WalletTxn {
  const WalletTxn({
    this.id,
    this.type,
    this.amount = 0,
    this.currency = 'USD',
    this.note,
    this.counterpartyId,
    this.counterpartyName,
    this.createdAt,
    this.raw = const {},
  });

  final String? id;
  final String? type;
  final num amount;
  final String currency;
  final String? note;
  final String? counterpartyId;
  final String? counterpartyName;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory WalletTxn.fromJson(Map<String, dynamic> json) {
    final amount = asDoubleOrNull(json['amount']) ?? 0;
    // The counterparty is the *other* user: for outgoing money that's the
    // recipient (to_user_id), for incoming it's the sender (from_user_id).
    final other = amount < 0
        ? json['to_user_id'] ?? json['from_user_id']
        : json['from_user_id'] ?? json['to_user_id'];
    return WalletTxn(
      id: asStringOrNull(json['id']),
      type: asStringOrNull(json['type']),
      amount: amount,
      currency: asString(json['currency'], 'USD'),
      note: asStringOrNull(json['note']),
      counterpartyId: asStringOrNull(json['counterparty_id'] ?? other),
      counterpartyName: asStringOrNull(json['counterparty_name']),
      createdAt: asDateOrNull(json['created_at']),
      raw: json,
    );
  }

  /// Normalized display status. Backends report many raw states; the UI
  /// shows exactly: Pending, Canceled, Failed, Reversed or Approved
  /// (the default for completed/settled/absent statuses).
  String get statusLabel {
    final s = '${raw['status'] ?? raw['state'] ?? ''}'.toLowerCase();
    if (s.contains('cancel')) return 'Canceled';
    if (s.contains('revers') || s.contains('refund')) return 'Reversed';
    if (s.contains('fail') ||
        s.contains('decline') ||
        s.contains('reject') ||
        s.contains('error')) {
      return 'Failed';
    }
    if (s.contains('pend') ||
        s.contains('process') ||
        s.contains('hold') ||
        s.contains('await') ||
        s.contains('requires') ||
        s == 'open' ||
        s == 'created') {
      return 'Pending';
    }
    return 'Approved';
  }

  bool get isSettled => statusLabel == 'Approved';
}

/// Summary of the authenticated user's wallet (earnings + spending).
class WalletSummary {
  const WalletSummary({
    this.currency = 'USD',
    this.balance = 0,
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.tipsTotal = 0,
    this.subsTotal = 0,
    this.adsTotal = 0,
    this.activeSubscribers = 0,
    this.subPrice = 0,
    this.recent = const [],
    this.sent = const [],
    this.raw = const {},
  });

  final String currency;
  final num balance;
  final num totalEarned;
  final num totalSpent;
  final num tipsTotal;
  final num subsTotal;
  final num adsTotal;
  final int activeSubscribers;
  final num subPrice;
  final List<WalletTxn> recent;
  final List<WalletTxn> sent;
  final Map<String, dynamic> raw;

  factory WalletSummary.fromJson(Map<String, dynamic> json) => WalletSummary(
        currency: asString(json['currency'], 'USD'),
        balance: asDoubleOrNull(json['balance']) ?? 0,
        totalEarned: asDoubleOrNull(json['total_earned']) ?? 0,
        totalSpent: asDoubleOrNull(json['total_spent']) ?? 0,
        tipsTotal: asDoubleOrNull(json['tips_total']) ?? 0,
        subsTotal: asDoubleOrNull(json['subs_total']) ?? 0,
        adsTotal: asDoubleOrNull(json['ads_total']) ?? 0,
        activeSubscribers: asInt(json['active_subscribers']),
        subPrice: asDoubleOrNull(json['sub_price']) ?? 0,
        recent: asModelList(json['recent'], WalletTxn.fromJson),
        sent: asModelList(json['sent'], WalletTxn.fromJson),
        raw: json,
      );
}
