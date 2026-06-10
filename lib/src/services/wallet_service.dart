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

  Future<dynamic> topups() => _client.getJson('/wallet/topups');

  Future<void> cancelTopup(String topupId) async {
    await _client.postJson('/wallet/topup/$topupId/cancel');
  }

  // --- Money: send / request ----------------------------------------------

  /// Sends money to another user. [answer] satisfies the recipient's or
  /// sender's security challenge when one is configured.
  Future<Map<String, dynamic>> sendMoney({
    required String toUserId,
    required num amount,
    required String answer,
    String? note,
  }) async =>
      asMapOrNull(await _client.postJson('/money/send', body: {
        'to_user_id': toUserId,
        'amount': amount,
        'answer': answer,
        if (note != null) 'note': note,
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

  Future<void> payRequest(String requestId, {String? answer}) async {
    await _client.postJson('/money/requests/$requestId/pay',
        body: {if (answer != null) 'answer': answer});
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

  Future<void> acceptTransfer(String transferId) async {
    await _client.postJson('/money/transfers/$transferId/accept');
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
