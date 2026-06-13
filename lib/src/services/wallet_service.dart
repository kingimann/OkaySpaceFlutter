import '../core/api_client.dart';
import '../models/json.dart';
import '../models/wallet.dart';

/// Endpoints under `/wallet` and `/money`: balance, transfers, money
/// requests and top-ups.
///
/// Money transfers can require a security answer (see [setSecurity] /
/// [getSecurity]); pass it via [sendMoney]'s `answer`.
class WalletService {
  WalletService(this._client);

  final ApiClient _client;

  /// Full wallet summary (balance, earnings, recent transactions).
  Future<WalletSummary> summary() async =>
      WalletSummary.fromJson(asMapOrNull(await _client.getJson('/wallet')) ?? const {});

  /// Lightweight balance check.
  Future<dynamic> balance() => _client.getJson('/wallet/balance');

  /// Full activity export (CSV/text payload, returned raw).
  Future<dynamic> export() => _client.getJson('/wallet/export');

  /// Wallet activity feed (raw payload).
  Future<dynamic> activity() => _client.getJson('/wallet/activity');

  /// Sets the wallet's display currency.
  Future<void> setCurrency(String currency) async {
    await _client.postJson('/wallet/currency', body: {'currency': currency});
  }

  // --- Top-ups ------------------------------------------------------------

  /// Starts a top-up and returns the provider payment intent/payload.
  Future<Map<String, dynamic>> topupIntent(num amount,
          {String? currency}) async =>
      asMapOrNull(await _client.postJson('/wallet/topup/intent', body: {
        'amount': amount,
        if (currency != null) 'currency': currency,
      })) ??
      const {};

  /// Confirms a top-up payment intent.
  Future<Map<String, dynamic>> confirmTopupIntent(
          Map<String, dynamic> body) async =>
      asMapOrNull(await _client.postJson('/wallet/topup/confirm-intent', body: body)) ??
      const {};

  /// Reconciles pending top-ups with Stripe (credits any that completed
  /// while the app wasn't watching, e.g. via Payment Link).
  Future<void> topupSync() async {
    await _client.postJson('/wallet/topup/sync');
  }

  Future<dynamic> topups() => _client.getJson('/wallet/topups');

  Future<void> cancelTopup(String topupId) async {
    await _client.postJson('/wallet/topup/$topupId/cancel');
  }

  // --- Money: send / request ----------------------------------------------

  /// Sends money to another user.
  ///
  /// [answer] satisfies the recipient's own pre-set security challenge.
  /// [securityQuestion]/[securityAnswer] add an Interac-style per-transfer
  /// challenge the SENDER sets: if the recipient doesn't auto-deposit, they
  /// must answer it to accept. Share the answer with them out of band.
  Future<Map<String, dynamic>> sendMoney({
    required String toUserId,
    required num amount,
    required String answer,
    String? note,
    String? securityQuestion,
    String? securityAnswer,
  }) async =>
      asMapOrNull(await _client.postJson('/money/send', body: {
        'to_user_id': toUserId,
        'amount': amount,
        'answer': answer,
        if (note != null) 'note': note,
        if (securityQuestion != null && securityQuestion.isNotEmpty)
          'security_question': securityQuestion,
        if (securityAnswer != null && securityAnswer.isNotEmpty)
          'security_answer': securityAnswer,
      })) ??
      const {};

  /// Requests money from another user.
  Future<Map<String, dynamic>> requestMoney({
    required String toUserId,
    required num amount,
    String? note,
  }) async =>
      asMapOrNull(await _client.postJson('/money/request', body: {
        'to_user_id': toUserId,
        'amount': amount,
        if (note != null) 'note': note,
      })) ??
      const {};

  Future<dynamic> moneyRequests() => _client.getJson('/money/requests');

  /// Pays a money request. Paying always requires the payer's transfer
  /// security answer (the backend's `PayRequest.answer` is required and
  /// `security_not_set`/wrong-answer is reported as a 400), so always send the
  /// field — an empty string surfaces the actionable error instead of a 422.
  Future<void> payRequest(String requestId, {String? answer}) async {
    await _client.postJson('/money/requests/$requestId/pay',
        body: {'answer': answer ?? ''});
  }

  Future<void> declineRequest(String requestId) async {
    await _client.postJson('/money/requests/$requestId/decline');
  }

  Future<void> cancelRequest(String requestId) async {
    await _client.postJson('/money/requests/$requestId/cancel');
  }

  // --- Transfers ----------------------------------------------------------

  Future<dynamic> transfers() => _client.getJson('/money/transfers');

  Future<dynamic> transferHistory() => _client.getJson('/money/transfers/history');

  /// Accepts a pending incoming transfer. [answer] satisfies the sender's
  /// per-transfer security question when one was set (Interac-style).
  Future<void> acceptTransfer(String transferId, {String? answer}) async {
    await _client.postJson('/money/transfers/$transferId/accept',
        body: {if (answer != null && answer.isNotEmpty) 'answer': answer});
  }

  /// Whether incoming transfers auto-deposit (skip the security question).
  Future<dynamic> autoDeposit() => _client.getJson('/money/auto-deposit');

  Future<void> setAutoDeposit(bool enabled) async {
    await _client
        .postJson('/money/auto-deposit', body: {'enabled': enabled});
  }

  Future<void> declineTransfer(String transferId) async {
    await _client.postJson('/money/transfers/$transferId/decline');
  }

  /// Reverses a recent outgoing transfer (within the reversal window).
  Future<void> reverseTransfer(String transferId) async {
    await _client.postJson('/money/transfers/$transferId/reverse');
  }

  // --- Security -----------------------------------------------------------

  /// The current money-transfer security configuration.
  Future<dynamic> getSecurity() => _client.getJson('/money/security');

  /// Sets the money-transfer security question/answer.
  Future<void> setSecurity(Map<String, dynamic> body) async {
    await _client.postJson('/money/security', body: body);
  }
}
