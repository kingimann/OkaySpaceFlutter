// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

import 'http_transport.dart';

Future<RawResponse> send(HttpRequestData r) async {
  html.HttpRequest req;
  try {
    req = await html.HttpRequest.request(
      r.url.toString(),
      method: r.method,
      requestHeaders: r.headers,
      sendData: r.body,
    ).timeout(r.timeout);
  } on TimeoutException catch (e) {
    throw TransportFailure('The connection timed out. Please try again.',
        timedOut: true, cause: e);
  } catch (e) {
    // The browser API errors for any non-2xx status as well as for real
    // transport failures; when a response exists, recover it so callers can
    // read the backend's error payload.
    if (e is html.ProgressEvent && e.target is html.HttpRequest) {
      final t = e.target as html.HttpRequest;
      final status = t.status ?? 0;
      if (status != 0) return RawResponse(status, t.responseText ?? '');
    }
    throw TransportFailure('Could not reach the server. Check your connection.',
        cause: e);
  }
  return RawResponse(req.status ?? 0, req.responseText ?? '');
}

void close({bool force = false}) {/* the browser pools connections itself */}
