/// Native stub: no browser download mechanism — callers fall back to
/// the clipboard/share path.
Future<bool> saveTextFile(String filename, String text,
        {String mimeType = 'text/csv'}) async =>
    false;
