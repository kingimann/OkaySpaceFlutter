import 'dart:math';

import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/payments`: checkout, payment intents, paying from wallet,
/// identity verification and Stripe-backed payout setup.
///
/// These endpoints return provider-specific payloads (client secrets, account
/// sessions, statuses), so methods return raw maps rather than typed models.
class PaymentsService {
  PaymentsService(this._client);

  final ApiClient _client;

  Map<String, dynamic> _map(Object? d) => asMapOrNull(d) ?? const {};

  /// Public payment configuration (e.g. Stripe publishable key).
  Future<Map<String, dynamic>> config() async =>
      _map(await _client.getJson('/payments/config'));

  /// Feature discovery: which rails/components/kinds this backend supports
  /// (stripe_rails, instant_payouts, checkout_kinds, embedded_components…).
  Future<Map<String, dynamic>> capabilities() async =>
      _map(await _client.getJson('/capabilities'));

  /// A fresh idempotency key: one per logical money operation, so a
  /// timed-out retry can never double-move funds.
  static String newIdempotencyKey() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0')
    ].join();
  }

  /// Starts a hosted checkout session and returns its URL/id.
  Future<Map<String, dynamic>> checkout(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/payments/checkout', body: body));

  /// Creates a PaymentIntent and returns its client secret.
  Future<Map<String, dynamic>> createPayIntent(
          Map<String, dynamic> body) async =>
      _map(await _client.postJson('/payments/pay-intent', body: body));

  /// Confirms a PaymentIntent.
  Future<Map<String, dynamic>> confirmPayIntent(
          Map<String, dynamic> body) async =>
      _map(await _client.postJson('/payments/pay-intent/confirm', body: body));

  /// Pays for something directly from the wallet balance.
  Future<Map<String, dynamic>> payWithWallet(
          Map<String, dynamic> body) async =>
      _map(await _client.postJson('/payments/pay-wallet', body: body));

  // --- Identity verification ----------------------------------------------

  Future<Map<String, dynamic>> startIdentity() async =>
      _map(await _client.postJson('/payments/identity/start'));

  Future<Map<String, dynamic>> identityStatus() async =>
      _map(await _client.getJson('/payments/identity/status'));

  // --- Payouts (Stripe Connect) -------------------------------------------

  Future<Map<String, dynamic>> setupPayouts() async =>
      _map(await _client.postJson('/payments/payouts/setup'));

  Future<Map<String, dynamic>> payoutStatus() async =>
      _map(await _client.getJson('/payments/payouts/status'));

  Future<Map<String, dynamic>> payoutRequirements() async =>
      _map(await _client.getJson('/payments/payouts/requirements'));

  /// Creates an embedded account session for the payouts onboarding UI.
  Future<Map<String, dynamic>> payoutAccountSession() async =>
      _map(await _client.postJson('/payments/payouts/account-session'));

  /// Requests a cash-out of available payout balance.
  Future<Map<String, dynamic>> cashout(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/payments/payouts/cashout', body: body));

  /// Sets how often the user gets paid automatically:
  /// manual | weekly | biweekly | monthly. Weekly/biweekly require a
  /// [weeklyAnchor] day name (e.g. 'friday'); monthly requires a
  /// [monthlyAnchor] day-of-month (1-31, clamped server-side).
  Future<Map<String, dynamic>> setPayoutSchedule(
    String interval, {
    String? weeklyAnchor,
    int? monthlyAnchor,
  }) async =>
      _map(await _client.postJson('/payments/payouts/schedule', body: {
        'interval': interval,
        if (interval == 'weekly' || interval == 'biweekly')
          'weekly_anchor': weeklyAnchor ?? 'friday',
        if (interval == 'monthly') 'monthly_anchor': monthlyAnchor ?? 1,
      }));

  /// The current automatic-payout schedule ({interval: ...}).
  Future<Map<String, dynamic>> payoutSchedule() async =>
      _map(await _client.getJson('/payments/payouts/schedule'));

  /// Adds a debit card as payout destination ([token] is a Stripe card
  /// token created client-side; raw card numbers never reach the backend).
  Future<Map<String, dynamic>> addDebitCard(String token) async =>
      _map(await _client
          .postJson('/payments/payouts/debit-card', body: {'token': token}));

  /// Adds a bank account as payout destination ([token] is a Stripe token).
  Future<Map<String, dynamic>> addBankAccount(String token) async =>
      _map(await _client
          .postJson('/payments/payouts/bank-account', body: {'token': token}));

  /// Saved payout destinations (debit cards + bank accounts) with brand/
  /// last4/default, for the "Visa •• 4242" list.
  Future<dynamic> payoutMethods() =>
      _client.getJson('/payments/payouts/methods');

  Future<void> deletePayoutMethod(String methodId) async {
    await _client.deleteJson('/payments/payouts/methods/$methodId');
  }

  Future<Map<String, dynamic>> setDefaultPayoutMethod(
          String methodId) async =>
      _map(await _client
          .postJson('/payments/payouts/methods/$methodId/default'));

  // --- Stripe Connect money rails ------------------------------------------
  // The wallet's Stripe-native endpoints: balance/transactions live at
  // Stripe, transfers move money user→user, payouts cash out (optionally
  // instant to a debit card).

  /// Creates/fetches the user's Stripe connected account.
  Future<Map<String, dynamic>> stripeAccount() async =>
      _map(await _client.postJson('/stripe/account'));

  /// The user's Stripe balance (available/pending).
  Future<Map<String, dynamic>> stripeBalance() async =>
      _map(await _client.getJson('/stripe/balance'));

  /// The user's Stripe balance transactions.
  Future<dynamic> stripeTransactions() =>
      _client.getJson('/stripe/transactions');

  /// Sends money to another user over Stripe. A fresh idempotency key is
  /// minted per call so transport retries can't double-send.
  Future<Map<String, dynamic>> stripeTransfer({
    required String toUserId,
    required num amount,
    String? note,
    String? idempotencyKey,
  }) async =>
      _map(await _client.postJson('/stripe/transfer',
          body: {
            'to_user_id': toUserId,
            'amount': amount,
            if (note != null) 'note': note,
          },
          headers: {
            'Idempotency-Key': idempotencyKey ?? newIdempotencyKey()
          }));

  /// Pays out to the user's bank/debit card. [instant] uses Stripe Instant
  /// Payouts (debit card required; Stripe charges its instant fee).
  Future<Map<String, dynamic>> stripePayout(
          {required num amount,
          bool instant = false,
          String? idempotencyKey}) async =>
      _map(await _client.postJson('/stripe/payout',
          body: {'amount': amount, 'instant': instant},
          headers: {
            'Idempotency-Key': idempotencyKey ?? newIdempotencyKey()
          }));

  // --- Developer API billing ----------------------------------------------

  Future<Map<String, dynamic>> apiPlan() async =>
      _map(await _client.getJson('/payments/api-plan'));

  Future<Map<String, dynamic>> apiUsage() async =>
      _map(await _client.getJson('/payments/api-usage'));
}
