import 'dart:async';
import 'dart:convert';

import 'api_config.dart';
import 'api_exception.dart';
import 'http_transport.dart';
import 'token_store.dart';

/// Hand-written client for the OkaySpace API — no third-party networking.
///
/// Handles the cross-cutting concerns shared by every endpoint: base URL,
/// bearer auth, JSON encoding/decoding, and turning failures into
/// [ApiException]. Services receive an [ApiClient] and call [getJson],
/// [postJson], etc. rather than touching the transport directly.
class ApiClient {
  ApiClient({
    ApiConfig config = const ApiConfig(),
    TokenStore? tokenStore,
    HttpSend? transport,
  })  : _config = config,
        tokenStore = tokenStore ?? SecureTokenStore(),
        _transport = transport ?? sendHttp;

  final ApiConfig _config;
  final TokenStore tokenStore;
  final HttpSend _transport;

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
    Map<String, String>? headers,
  }) =>
      _send('POST', path, body: body, query: query, extraHeaders: headers);

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
    Map<String, String>? extraHeaders,
  }) async {
    final encoded = body == null ? null : jsonEncode(body);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (encoded != null) 'Content-Type': 'application/json',
      ...?extraHeaders,
    };
    final token = await tokenStore.read();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final RawResponse res;
    try {
      res = await _transport(HttpRequestData(
        method: method,
        url: _resolve(path, query),
        headers: headers,
        body: encoded,
        timeout: _config.receiveTimeout,
      ));
    } on TransportFailure catch (e) {
      throw ApiException.network(e.message, cause: e);
    } on TimeoutException catch (e) {
      throw ApiException.network(
          'The connection timed out. Please try again.',
          cause: e);
    }

    final data = _decode(res.body);
    if (res.status >= 400) {
      // An expired/invalid credential: drop it and notify the app so it can
      // return to the login screen instead of failing every request.
      if (res.status == 401) {
        await tokenStore.clear();
        onUnauthorized?.call();
      }
      throw ApiException.fromResponse(res.status, data);
    }
    return data;
  }

  /// Joins the base URL, path and query (null values dropped, list values
  /// repeated as `?k=a&k=b`).
  Uri _resolve(String path, Map<String, dynamic>? query) {
    final base = Uri.parse('${_config.baseUrl}$path');
    final params = <String, dynamic>{};
    query?.forEach((key, value) {
      if (value == null) return;
      params[key] = value is List ? [for (final v in value) '$v'] : '$value';
    });
    return params.isEmpty ? base : base.replace(queryParameters: params);
  }

  /// Empty bodies become null; non-JSON bodies are returned as raw text.
  dynamic _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  /// Closes the underlying HTTP client.
  void close({bool force = false}) => closeHttp(force: force);
}
