import '../core/api_client.dart';
import '../models/json.dart';

/// Endpoints under `/oauth`: managing your OAuth apps, the authorization code
/// flow, token exchange, and the connections other apps hold to your account.
class OAuthService {
  OAuthService(this._client);

  final ApiClient _client;

  Map<String, dynamic> _map(Object? d) => asMapOrNull(d) ?? const {};

  // --- Your OAuth apps (developer) ----------------------------------------

  /// OAuth apps you've registered.
  Future<dynamic> apps() => _client.getJson('/oauth/apps');

  /// Registers a new OAuth app (name, redirect URIs, scopes…). Returns the
  /// client id/secret.
  Future<Map<String, dynamic>> createApp(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/oauth/apps', body: body));

  /// Public metadata for an app by client id.
  Future<Map<String, dynamic>> app(String clientId) async =>
      _map(await _client.getJson('/oauth/app/$clientId'));

  Future<void> deleteApp(String clientId) async {
    await _client.deleteJson('/oauth/apps/$clientId');
  }

  // --- Authorization flow -------------------------------------------------

  /// Approves an authorization request and returns the authorization code.
  Future<Map<String, dynamic>> authorize(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/oauth/authorize', body: body));

  /// Exchanges an authorization code (or refresh token) for access tokens.
  Future<Map<String, dynamic>> token(Map<String, dynamic> body) async =>
      _map(await _client.postJson('/oauth/token', body: body));

  /// Revokes a token.
  Future<void> revoke(Map<String, dynamic> body) async {
    await _client.postJson('/oauth/revoke', body: body);
  }

  /// OpenID-style profile for the bearer token.
  Future<Map<String, dynamic>> userInfo() async =>
      _map(await _client.getJson('/oauth/userinfo'));

  // --- Connections you've granted to other apps ---------------------------

  Future<dynamic> connections() => _client.getJson('/oauth/connections');

  Future<void> revokeConnection(String clientId) async {
    await _client.deleteJson('/oauth/connections/$clientId');
  }
}
