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

  // --- Developer API billing ----------------------------------------------

  Future<Map<String, dynamic>> apiPlan() async =>
      _map(await _client.getJson('/payments/api-plan'));

  Future<Map<String, dynamic>> apiUsage() async =>
      _map(await _client.getJson('/payments/api-usage'));
}
