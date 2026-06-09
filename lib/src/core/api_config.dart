/// Configuration for talking to the OkaySpace REST API.
///
/// The backend exposes a versioned base (`/api/v1`) and a legacy unversioned
/// base (`/api`). We default to the versioned one.
class ApiConfig {
  const ApiConfig({
    this.baseUrl = productionV1,
    this.connectTimeout = const Duration(seconds: 20),
    this.receiveTimeout = const Duration(seconds: 30),
  });

  /// Production, versioned API (recommended).
  static const String productionV1 = 'https://nampo-backend.onrender.com/api/v1';

  /// Production, unversioned legacy API.
  static const String productionLegacy = 'https://nampo-backend.onrender.com/api';

  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
}
