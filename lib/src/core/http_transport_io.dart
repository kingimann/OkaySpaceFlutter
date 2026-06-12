import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_transport.dart';

// One shared client so keep-alive connections are reused across requests.
HttpClient? _client;
HttpClient get _shared => _client ??= HttpClient();

Future<RawResponse> send(HttpRequestData r) async {
  final client = _shared..connectionTimeout = r.timeout;
  try {
    final req = await client.openUrl(r.method, r.url).timeout(r.timeout);
    r.headers.forEach(req.headers.set);
    final body = r.body;
    if (body != null) {
      final bytes = utf8.encode(body);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(r.timeout);
    final text = await utf8.decodeStream(res).timeout(r.timeout);
    return RawResponse(res.statusCode, text);
  } on TimeoutException catch (e) {
    throw TransportFailure('The connection timed out. Please try again.',
        timedOut: true, cause: e);
  } on SocketException catch (e) {
    throw TransportFailure('Could not reach the server. Check your connection.',
        cause: e);
  } on HandshakeException catch (e) {
    throw TransportFailure('A secure connection could not be established.',
        cause: e);
  } on HttpException catch (e) {
    throw TransportFailure('A network error occurred.', cause: e);
  }
}

void close({bool force = false}) {
  _client?.close(force: force);
  _client = null;
}
