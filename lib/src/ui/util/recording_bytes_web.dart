// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Web: `record` returns a blob URL; fetch it to get the bytes.
Future<Uint8List?> readRecording(String url) async {
  try {
    final resp = await html.HttpRequest.request(url, responseType: 'arraybuffer');
    final buf = resp.response;
    if (buf is ByteBuffer) return buf.asUint8List();
    return null;
  } catch (_) {
    return null;
  }
}
