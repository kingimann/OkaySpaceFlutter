import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/admin`: moderation, finance, support and platform ops.
///
/// Requires an admin account. Responses are operational payloads, returned raw.
class AdminService {
  AdminService(this._client);

  final ApiClient _client;

  Map<String, dynamic> _map(Object? d) => asMapOrNull(d) ?? const {};

  // --- Users & moderation -------------------------------------------------

  /// Searches/paginates users.
  Future<dynamic> users({String? query, int? limit, int? offset}) =>
      _client.getJson('/admin/users',
          query: {'q': query, 'limit': limit, 'offset': offset});

  /// Updates a user record.
  Future<Map<String, dynamic>> updateUser(
          String userId, Map<String, dynamic> changes) async =>
      _map(await _client.patchJson('/admin/users/$userId', body: changes));

  Future<void> deleteUser(String userId) async {
    await _client.deleteJson('/admin/users/$userId');
  }

  Future<void> banUser(String userId, {String? reason}) async {
    await _client.postJson('/admin/users/$userId/ban',
        body: {if (reason != null) 'reason': reason});
  }

  Future<void> unbanUser(String userId) async {
    await _client.postJson('/admin/users/$userId/unban');
  }

  Future<void> suspendUser(String userId, {int? days, String? reason}) async {
    await _client.postJson('/admin/users/$userId/suspend', body: {
      if (days != null) 'days': days,
      if (reason != null) 'reason': reason,
    });
  }

  /// Sets per-user feature restrictions (messaging/posting/marketplace…).
  Future<void> setRestrictions(
      String userId, Map<String, dynamic> restrictions) async {
    await _client.postJson('/admin/users/$userId/restrictions',
        body: restrictions);
  }

  Future<void> grantBadge(String userId, Map<String, dynamic> body) async {
    await _client.postJson('/admin/users/$userId/badge', body: body);
  }

  // --- User finance -------------------------------------------------------

  Future<dynamic> userTransactions(String userId) =>
      _client.getJson('/admin/users/$userId/transactions');

  Future<Map<String, dynamic>> addTransaction(
          String userId, Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/users/$userId/transaction',
          body: body));

  /// Sets a user's wallet balance directly.
  Future<Map<String, dynamic>> setWallet(
          String userId, Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/users/$userId/wallet', body: body));

  // --- Stripe reconciliation ----------------------------------------------

  /// Looks up an email's real Stripe payments: each charge, per-currency
  /// gross/refunded/net, and the matching app user's current wallet.
  Future<Map<String, dynamic>> stripeLookup(String email) async =>
      _map(await _client.getJson('/admin/stripe/lookup',
          query: {'email': email}));

  /// Sets a user's wallet balance to a verified amount (from the lookup).
  Future<Map<String, dynamic>> stripeReconcile(
          {String? userId, String? email, required double amount}) async =>
      _map(await _client.postJson('/admin/stripe/reconcile', body: {
        'amount': amount,
        if (userId != null) 'user_id': userId,
        if (email != null) 'email': email,
      }));

  // --- Legal documents ----------------------------------------------------

  /// Current Terms of Service & Privacy Policy text (public endpoint).
  Future<Map<String, dynamic>> legal() async =>
      _map(await _client.getJson('/legal'));

  /// Edits the Terms of Service and/or Privacy Policy (admin only).
  Future<Map<String, dynamic>> updateLegal(
          {String? terms, String? privacy, String? effectiveDate}) async =>
      _map(await _client.postJson('/admin/legal', body: {
        if (terms != null) 'terms': terms,
        if (privacy != null) 'privacy': privacy,
        if (effectiveDate != null) 'effective_date': effectiveDate,
      }));

  // --- Platform finance ---------------------------------------------------

  Future<dynamic> revenue() => _client.getJson('/admin/revenue');
  Future<dynamic> adRevenue() => _client.getJson('/admin/ad-revenue');

  Future<dynamic> fees() => _client.getJson('/admin/fees');
  Future<Map<String, dynamic>> setFees(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/fees', body: body));

  // --- Audit, support & moderation queues ---------------------------------

  Future<dynamic> auditLog({int? limit}) =>
      _client.getJson('/admin/audit', query: {'limit': limit});

  Future<dynamic> supportTickets({String? status}) =>
      _client.getJson('/admin/support/tickets', query: {'status': status});

  Future<dynamic> roadsideVerifications({String? status}) => _client
      .getJson('/admin/roadside/verifications', query: {'status': status});

  Future<Map<String, dynamic>> decideRoadsideVerification(
          String verificationId, Map<String, dynamic> body) async =>
      _map(await _client.postJson(
          '/admin/roadside/verifications/$verificationId/decision',
          body: body));

  // --- Badges -------------------------------------------------------------

  Future<Map<String, dynamic>> createBadge(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/badges', body: body));

  Future<void> deleteBadge(String badgeId) async {
    await _client.deleteJson('/admin/badges/$badgeId');
  }

  Future<dynamic> listBadges() => _client.getJson('/admin/badges');

  Future<Map<String, dynamic>> editTransaction(String userId, String txnId,
          Map<String, dynamic> changes) async =>
      _map(await _client.patchJson('/admin/users/$userId/transaction',
          body: {'ref': txnId, ...changes}));

  Future<void> deleteTransaction(String userId, String txnId,
      {bool adjust = false}) async {
    await _client.deleteJson('/admin/users/$userId/transaction',
        query: {'ref': txnId, 'adjust_balance': adjust});
  }

  // --- Platform switches & resets ------------------------------------------

  Future<dynamic> testPayments() => _client.getJson('/admin/test-payments');
  Future<void> setTestPayments(bool on) async {
    await _client.postJson('/admin/test-payments', body: {'enabled': on});
  }

  Future<dynamic> mobileOnly() => _client.getJson('/admin/mobile-only');
  Future<void> setMobileOnly(bool on) async {
    await _client.postJson('/admin/mobile-only', body: {'enabled': on});
  }

  /// Whether phone browsers are nudged toward the native app.
  Future<dynamic> mobileWebGate() => _client.getJson('/admin/mobile-web-gate');
  Future<void> setMobileWebGate(bool on) async {
    await _client.postJson('/admin/mobile-web-gate', body: {'enabled': on});
  }

  // --- Registration & invites --------------------------------------------

  /// Current registration mode ('open' | 'invite' | 'closed').
  Future<dynamic> registrationMode() =>
      _client.getJson('/admin/registration');

  Future<void> setRegistrationMode(String mode) async {
    await _client.postJson('/admin/registration', body: {'mode': mode});
  }

  /// Existing invite codes.
  Future<dynamic> invites() => _client.getJson('/admin/invites');

  /// Creates [count] invite codes (returns the new codes).
  Future<Map<String, dynamic>> createInvites({int count = 1}) async =>
      _map(await _client.postJson('/admin/invites', body: {'count': count}));

  Future<void> deleteInvite(String code) async {
    await _client.deleteJson('/admin/invites/$code');
  }

  Future<dynamic> webBuild() => _client.getJson('/admin/web-build');
  /// Bumps the web-build token so open tabs prompt to reload. Posting with no
  /// build lets the backend mint a fresh token.
  Future<void> bumpWebBuild() async {
    await _client.postJson('/admin/web-build');
  }

  Future<void> resetMoney() async {
    await _client.postJson('/admin/reset/money');
  }

  /// Removes posts whose author no longer exists (deleted-user posts).
  /// Returns {removed, scanned}.
  Future<Map<String, dynamic>> cleanupOrphanedPosts() async =>
      _map(await _client.postJson('/admin/cleanup/orphaned-posts'));

  Future<void> resetAnalytics() async {
    await _client.postJson('/admin/reset/analytics');
  }

  // --- Test bot -------------------------------------------------------------

  Future<dynamic> botPosts() => _client.getJson('/admin/bot/posts');

  Future<Map<String, dynamic>> runBot(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/bot/run', body: body));

  // --- Roadside calls -------------------------------------------------------
  // Dispatch/test entries (no wallet charge); live under /roadside/admin.

  Future<Map<String, dynamic>> createRoadsideCall(
          Map<String, dynamic> body) async =>
      _map(await _client.postJson('/roadside/admin/calls', body: body));

  Future<dynamic> roadsideCalls({String? date, String? callNumber}) =>
      _client.getJson('/roadside/admin/calls',
          query: {'date': date, 'call_number': callNumber});

  Future<void> deleteRoadsideCall(String callId) async {
    await _client.deleteJson('/roadside/admin/calls/$callId');
  }

  /// Bulk-erase calls. Scope is explicit and never defaults to "all":
  /// pass [date] for one day, [testOnly] for admin-created test calls, or
  /// [all]:true to purge everything. `all` is only sent when no narrower
  /// scope is given, so the test-only button can't carry an all=true that
  /// the backend might honor over test_only.
  Future<void> eraseRoadsideCalls(
      {bool testOnly = false, bool all = false, String? date}) async {
    final purgeEverything = all && date == null && !testOnly;
    await _client.deleteJson('/roadside/admin/calls', query: {
      if (purgeEverything) 'all': true,
      if (date != null) 'date': date,
      'test_only': testOnly,
    });
  }

  // --- Render hosting -------------------------------------------------------

  Future<dynamic> renderServices() => _client.getJson('/admin/render/services');

  Future<dynamic> renderDeploys(String serviceId) =>
      _client.getJson('/admin/render/services/$serviceId/deploys');

  Future<Map<String, dynamic>> renderTriggerDeploy(String serviceId,
          {bool clearCache = false}) async =>
      _map(await _client.postJson('/admin/render/services/$serviceId/deploys',
          body: {'clear_cache': clearCache}));

  Future<void> renderRestart(String serviceId) async {
    await _client.postJson('/admin/render/services/$serviceId/restart');
  }

  Future<void> renderSuspend(String serviceId) async {
    await _client.postJson('/admin/render/services/$serviceId/suspend');
  }

  Future<void> renderResume(String serviceId) async {
    await _client.postJson('/admin/render/services/$serviceId/resume');
  }

  Future<dynamic> renderEnvVars(String serviceId) =>
      _client.getJson('/admin/render/services/$serviceId/env-vars');

  Future<void> renderSetEnv(String serviceId, String key, String value) async {
    await _client.putJson('/admin/render/services/$serviceId/env-vars/$key',
        body: {'value': value});
  }

  Future<void> renderDeleteEnv(String serviceId, String key) async {
    await _client
        .deleteJson('/admin/render/services/$serviceId/env-vars/$key');
  }

  // --- Integrations -------------------------------------------------------

  Future<dynamic> integrations({bool? live, String? only}) =>
      // The backend validates `live` as an integer (0/1), not a bool string.
      _client.getJson('/admin/integrations',
          query: {'live': live == null ? null : (live ? 1 : 0), 'only': only});
}
