import 'dart:convert';

import 'package:okayspace/okayspace_api.dart';

/// A routable fake HTTP transport for service-layer tests.
///
/// Register canned responses with [on] (matched by method + a path suffix),
/// build a client with [client], then assert on the recorded [requests]. This
/// lets a test drive a real service end to end — the path/method/body it sends
/// AND how it parses the reply — without any network.
class FakeApi {
  final List<HttpRequestData> requests = [];
  final List<_Route> _routes = [];

  /// Register a response. [pathSuffix] is matched against the end of the
  /// request URL path (e.g. '/circles', '/friends/u1'). [json] is encoded;
  /// pass [body] for a raw/empty string body instead.
  void on(
    String method,
    String pathSuffix, {
    int status = 200,
    Object? json,
    String? body,
  }) {
    _routes.add(_Route(
      method.toUpperCase(),
      pathSuffix,
      status,
      json != null ? jsonEncode(json) : (body ?? ''),
    ));
  }

  /// The most recent request whose path ends with [pathSuffix] (and method, if given).
  HttpRequestData request(String pathSuffix, {String? method}) => requests.lastWhere(
        (r) => r.url.path.endsWith(pathSuffix) &&
            (method == null || r.method == method.toUpperCase()),
        orElse: () => throw StateError('No request matched $pathSuffix'),
      );

  /// Decoded JSON body of the most recent matching request.
  Map<String, dynamic> body(String pathSuffix, {String? method}) {
    final raw = request(pathSuffix, method: method).body;
    return raw == null || raw.isEmpty
        ? const {}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  ApiClient client() => ApiClient(
        tokenStore: InMemoryTokenStore('tok'),
        transport: (r) async {
          requests.add(r);
          for (final route in _routes) {
            if (route.method == r.method && r.url.path.endsWith(route.pathSuffix)) {
              return RawResponse(route.status, route.body);
            }
          }
          throw StateError('Unexpected request: ${r.method} ${r.url.path}');
        },
      );
}

class _Route {
  _Route(this.method, this.pathSuffix, this.status, this.body);

  final String method;
  final String pathSuffix;
  final int status;
  final String body;
}
