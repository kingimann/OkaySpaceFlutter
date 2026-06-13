import '../core/api_client.dart';
import '../models/auth_response.dart';
import '../models/json.dart';
import '../models/user.dart';

/// Endpoints under `/auth`: registration, login, the current user and account
/// management.
///
/// On successful [register]/[login] the returned `session_token` is persisted
/// via the [ApiClient]'s token store, so subsequent calls are authenticated
/// automatically.
class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  /// Creates an account and signs in.
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String name,
    required String username,
    String? inviteCode,
  }) async {
    final data = await _client.postJson('/auth/register', body: {
      'email': email,
      'password': password,
      'name': name,
      'username': username,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode,
    });
    return _persist(AuthResponse.fromJson(asMapOrNull(data) ?? const {}));
  }

  /// Signs in with an email/username/phone [identifier] and password.
  ///
  /// If 2FA is enabled the response may omit a token; inspect
  /// [AuthResponse.raw] and follow up with [loginWith2fa].
  Future<AuthResponse> login({
    required String identifier,
    required String password,
  }) async {
    final data = await _client.postJson('/auth/login', body: {
      'identifier': identifier,
      'password': password,
    });
    return _persist(AuthResponse.fromJson(asMapOrNull(data) ?? const {}));
  }

  /// Completes a 2FA login challenge.
  Future<AuthResponse> loginWith2fa({
    required String challengeId,
    required String code,
  }) async {
    final data = await _client.postJson('/auth/login/2fa', body: {
      'challenge_id': challengeId,
      'code': code,
    });
    return _persist(AuthResponse.fromJson(asMapOrNull(data) ?? const {}));
  }

  /// The currently authenticated user.
  Future<User> me() async {
    final data = await _client.getJson('/auth/me');
    return User.fromJson(asMapOrNull(data) ?? const {});
  }

  /// Updates the current user's profile. Pass only the fields you want to
  /// change (see the `ProfilePatch` schema, e.g. `name`, `bio`, `picture`,
  /// `headline`, `location`, `accent_color`, `is_private`…).
  Future<User> updateProfile(Map<String, dynamic> changes) async {
    final data = await _client.patchJson('/auth/me', body: changes);
    return User.fromJson(asMapOrNull(data) ?? const {});
  }

  /// Changes the account password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.patchJson('/auth/me/password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Whether [username] is free to claim.
  Future<bool> isUsernameAvailable(String username) async {
    final data = await _client.getJson(
      '/auth/username-available',
      query: {'u': username},
    );
    if (data is Map) {
      return asBool(data['available'] ?? data['ok'] ?? data['result']);
    }
    return asBool(data);
  }

  /// Sends a password-reset email.
  Future<void> forgotPassword(String email) async {
    await _client.postJson('/auth/forgot-password', body: {'email': email});
  }

  // --- Account management -------------------------------------------------

  /// Enables or disables two-factor authentication (password required).
  Future<void> setTwoFactor(
      {required bool enabled, required String password}) async {
    await _client.postJson('/auth/2fa',
        body: {'enabled': enabled, 'password': password});
  }

  /// Changes the account username.
  Future<void> changeUsername(String username) async {
    await _client.postJson('/auth/username', body: {'username': username});
  }

  /// Changes the account email (requires the current password).
  Future<void> changeEmail(
      {required String currentPassword, required String newEmail}) async {
    await _client.patchJson('/auth/me/email',
        body: {'current_password': currentPassword, 'new_email': newEmail});
  }

  /// Sends a verification code to the current email.
  Future<void> sendEmailCode() async {
    await _client.postJson('/auth/email/send-code');
  }

  /// Verifies the current email with the emailed [code].
  Future<void> verifyEmail(String code) async {
    await _client.postJson('/auth/email/verify', body: {'code': code});
  }

  /// Sets/updates the account phone number.
  Future<void> changePhone(String phone) async {
    await _client.patchJson('/auth/me/phone', body: {'phone': phone});
  }

  /// Sends an SMS verification code to [phone].
  Future<void> sendPhoneCode(String phone) async {
    await _client.postJson('/auth/phone/send-code', body: {'phone': phone});
  }

  /// Verifies the phone with the SMS [code].
  Future<void> verifyPhone(String code) async {
    await _client.postJson('/auth/phone/verify', body: {'code': code});
  }

  /// Records the user's agreement to the current policies.
  Future<User> acceptPolicies() async {
    final data = await _client.postJson('/auth/accept-policies');
    return User.fromJson(asMapOrNull(data) ?? const {});
  }

  // --- Developer API keys -------------------------------------------------

  /// Creates a new API key. The full key value is typically only returned
  /// here, once — surface it to the user immediately.
  Future<Map<String, dynamic>> createApiKey({
    String? label,
    List<String>? scopes,
  }) async {
    final data = await _client.postJson('/auth/api-keys', body: {
      if (label != null) 'label': label,
      if (scopes != null) 'scopes': scopes,
    });
    return asMapOrNull(data) ?? const {};
  }

  /// Lists the account's API keys (without their secret values).
  Future<List<Map<String, dynamic>>> listApiKeys() async {
    final data = await _client.getJson('/auth/api-keys');
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  /// Revokes an API key by id.
  Future<void> revokeApiKey(String keyId) async {
    await _client.deleteJson('/auth/api-keys/$keyId');
  }

  // --- Session ------------------------------------------------------------

  /// Signs out: tells the backend and clears the locally stored token even if
  /// the network call fails.
  Future<void> logout() async {
    try {
      await _client.postJson('/auth/logout');
    } finally {
      await _client.clearToken();
    }
  }

  Future<AuthResponse> _persist(AuthResponse response) async {
    if (response.hasToken) {
      await _client.setToken(response.sessionToken!);
    }
    return response;
  }
}
