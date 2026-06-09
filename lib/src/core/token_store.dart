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

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String token) => _storage.write(key: key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: key);
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
