import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Triggers a real browser download of [text] as [filename].
Future<bool> saveTextFile(String filename, String text,
    {String mimeType = 'text/csv'}) async {
  try {
    final blob = web.Blob(
      [text.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename;
    web.document.body!.appendChild(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
