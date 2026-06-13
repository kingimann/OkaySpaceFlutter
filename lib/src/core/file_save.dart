/// Save-a-file facade: real download on web, false elsewhere (callers
/// fall back to clipboard/share).
library;

export 'file_save_stub.dart' if (dart.library.html) 'file_save_web.dart';
