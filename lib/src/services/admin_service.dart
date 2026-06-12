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
      _map(await _client.patchJson('/admin/users/$userId/transactions/$txnId',
          body: changes));

  Future<void> deleteTransaction(String userId, String txnId,
      {bool adjust = false}) async {
    await _client.deleteJson('/admin/users/$userId/transactions/$txnId',
        query: {'adjust': adjust});
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

  Future<dynamic> webBuild() => _client.getJson('/admin/web-build');
  Future<void> bumpWebBuild() async {
    await _client.postJson('/admin/web-build/bump');
  }

  Future<void> resetMoney() async {
    await _client.postJson('/admin/reset-money');
  }

  Future<void> resetAnalytics() async {
    await _client.postJson('/admin/reset-analytics');
  }

  // --- Test bot -------------------------------------------------------------

  Future<dynamic> botPosts() => _client.getJson('/admin/bot/posts');

  Future<Map<String, dynamic>> runBot(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/bot/run', body: body));

  // --- Roadside calls -------------------------------------------------------

  Future<Map<String, dynamic>> createRoadsideCall(
          Map<String, dynamic> body) async =>
      _map(await _client.postJson('/admin/roadside/calls', body: body));

  Future<dynamic> roadsideCalls({String? date, String? callNumber}) =>
      _client.getJson('/admin/roadside/calls',
          query: {'date': date, 'call_number': callNumber});

  Future<void> deleteRoadsideCall(String callId) async {
    await _client.deleteJson('/admin/roadside/calls/$callId');
  }

  Future<void> eraseRoadsideCalls({bool testOnly = false}) async {
    await _client
        .postJson('/admin/roadside/calls/erase', body: {'test_only': testOnly});
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
    await _client.postJson('/admin/render/services/$serviceId/env-vars',
        body: {'key': key, 'value': value});
  }

  Future<void> renderDeleteEnv(String serviceId, String key) async {
    await _client
        .deleteJson('/admin/render/services/$serviceId/env-vars/$key');
  }

  // --- Integrations -------------------------------------------------------

  Future<dynamic> integrations({bool? live, String? only}) =>
      _client.getJson('/admin/integrations', query: {'live': live, 'only': only});
}
