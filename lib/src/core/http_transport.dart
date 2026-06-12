import 'http_transport_io.dart'
    if (dart.library.html) 'http_transport_web.dart' as impl;

/// Hand-written HTTP transport — the app's only networking layer.
///
/// Natively this is `dart:io`'s [HttpClient]; on the web it is the browser's
/// XMLHttpRequest. There is no third-party HTTP dependency. [ApiClient] and
/// the Mapbox helpers sit on top of [sendHttp].

/// A raw HTTP response: status code plus the UTF-8 decoded body text
/// (every endpoint the app talks to speaks JSON).
class RawResponse {
  const RawResponse(this.status, this.body);

  final int status;
  final String body;
}

/// Everything a transport needs to perform one HTTP exchange.
class HttpRequestData {
  const HttpRequestData({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 30),
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// Request body as text (JSON), or null for body-less requests.
  final String? body;

  final Duration timeout;
}

/// Thrown by a transport when no HTTP response was produced at all
/// (connection refused, DNS failure, timeout…).
class TransportFailure implements Exception {
  TransportFailure(this.message, {this.timedOut = false, this.cause});

  final String message;
  final bool timedOut;
  final Object? cause;

  @override
  String toString() => 'TransportFailure: $message';
}

/// Signature of the function that performs one HTTP exchange. [ApiClient]
/// accepts one of these so tests can run without touching the network.
typedef HttpSend = Future<RawResponse> Function(HttpRequestData request);

/// Performs [request] on the platform transport.
Future<RawResponse> sendHttp(HttpRequestData request) => impl.send(request);

/// Releases any pooled connections held by the platform transport.
void closeHttp({bool force = false}) => impl.close(force: force);
