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

  Future<void> suspendUser(String userId, {String? reason}) async {
    await _client.postJson('/admin/users/$userId/suspend',
        body: {if (reason != null) 'reason': reason});
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

  // --- Integrations -------------------------------------------------------

  Future<dynamic> integrations({bool? live, String? only}) =>
      _client.getJson('/admin/integrations', query: {'live': live, 'only': only});
}
