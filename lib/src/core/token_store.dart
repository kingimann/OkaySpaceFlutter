import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the credential sent as `Authorization: Bearer <token>`.
///
/// This can hold either a session token (from login/register) or a long-lived
/// API key generated under Settings → Developer API.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Default implementation backed by the platform secure storage
/// (Keychain on iOS, Keystore-backed `EncryptedSharedPreferences` on Android,
/// WebCrypto on web).
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage, this.key = _defaultKey})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _defaultKey = 'okayspace.session_token';

  final FlutterSecureStorage _storage;
  final String key;

  // Secure storage backends can throw on some platforms (notably web, where
  // it depends on WebCrypto / a secure context). A storage failure must never
  // crash app startup, so reads degrade to "no token" and writes are best
  // effort.
  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: key, value: token);
    } catch (_) {/* best effort */}
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: key);
    } catch (_) {/* best effort */}
  }
}

/// In-memory store, handy for tests and ephemeral sessions.
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
