import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads [text] as a file named [filename] via a temporary object URL.
bool downloadText(String filename, String text) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = filename;
  a.style.setProperty('display', 'none');
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
