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

  // In-memory copy of the token for the current session. Secure storage
  // backends can throw or be flaky on some platforms (notably web, where it
  // depends on WebCrypto / a secure context). Caching here means the session
  // stays authenticated even if the persistent read later fails — which also
  // avoids a flaky read triggering a spurious 401 -> logout loop.
  String? _cached;
  bool _loaded = false;

  @override
  Future<String?> read() async {
    if (_cached != null) return _cached;
    if (_loaded) return _cached;
    try {
      _cached = await _storage.read(key: key);
    } catch (_) {
      _cached = null;
    }
    _loaded = true;
    return _cached;
  }

  @override
  Future<void> write(String token) async {
    _cached = token; // available immediately, regardless of persistence
    _loaded = true;
    try {
      await _storage.write(key: key, value: token);
    } catch (_) {/* best effort persistence */}
  }

  @override
  Future<void> clear() async {
    _cached = null;
    _loaded = true;
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
