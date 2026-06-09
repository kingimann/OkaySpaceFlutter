import 'json.dart';
import 'user.dart';

/// Returned by register/login: a session token plus the authenticated user.
///
/// Some auth flows (2FA, phone verification) may return a partial payload, so
/// both fields are tolerated as nullable and exposed via [raw].
class AuthResponse {
  const AuthResponse({this.sessionToken, this.user, this.raw = const {}});

  final String? sessionToken;
  final User? user;
  final Map<String, dynamic> raw;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final userJson = asMapOrNull(json['user']);
    return AuthResponse(
      sessionToken: asStringOrNull(json['session_token'] ?? json['token']),
      user: userJson != null ? User.fromJson(userJson) : null,
      raw: json,
    );
  }

  bool get hasToken => sessionToken != null && sessionToken!.isNotEmpty;
}
