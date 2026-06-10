import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// Thin wrapper around [Dio] that handles the cross-cutting concerns shared by
/// every OkaySpace endpoint: base URL, bearer auth, JSON parsing and turning
/// failures into [ApiException].
///
/// Services receive an [ApiClient] and call [getJson], [postJson], etc. rather
/// than touching Dio directly.
class ApiClient {
  ApiClient({
    ApiConfig config = const ApiConfig(),
    TokenStore? tokenStore,
    Dio? dio,
  })  : _config = config,
        tokenStore = tokenStore ?? SecureTokenStore(),
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = _config.baseUrl
      ..connectTimeout = _config.connectTimeout
      ..receiveTimeout = _config.receiveTimeout
      ..contentType = Headers.jsonContentType
      // We validate status ourselves so we can build rich exceptions.
      ..validateStatus = (status) => status != null && status < 400;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await this.tokenStore.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) {
          // An expired/invalid credential: drop it and notify the app so it
          // can return to the login screen instead of failing every request.
          if (e.response?.statusCode == 401) {
            this.tokenStore.clear();
            onUnauthorized?.call();
          }
          // Surface a normalized error to every caller.
          handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              error: ApiException.fromDio(e),
              response: e.response,
              type: e.type,
            ),
          );
        },
      ),
    );
  }

  final ApiConfig _config;
  final TokenStore tokenStore;
  final Dio _dio;

  /// Called once when a request is rejected with HTTP 401 (the stored
  /// credential has just been cleared). The app uses this to reset to login.
  void Function()? onUnauthorized;

  /// Whether a credential is currently stored.
  Future<bool> get isAuthenticated async {
    final token = await tokenStore.read();
    return token != null && token.isNotEmpty;
  }

  Future<void> setToken(String token) => tokenStore.write(token);
  Future<void> clearToken() => tokenStore.clear();

  // --- Verb helpers -------------------------------------------------------

  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send('GET', path, query: query);

  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('POST', path, body: body, query: query);

  Future<dynamic> patchJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('PATCH', path, body: body, query: query);

  Future<dynamic> putJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('PUT', path, body: body, query: query);

  Future<dynamic> deleteJson(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('DELETE', path, body: body, query: query);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: _clean(query),
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (e) {
      // The interceptor already wrapped it; unwrap and rethrow cleanly.
      final wrapped = e.error;
      throw wrapped is ApiException ? wrapped : ApiException.fromDio(e);
    }
  }

  /// Drops null query values so we don't send `?foo=null`.
  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final cleaned = <String, dynamic>{};
    query.forEach((key, value) {
      if (value != null) cleaned[key] = value;
    });
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Closes the underlying HTTP client.
  void close({bool force = false}) => _dio.close(force: force);
}
