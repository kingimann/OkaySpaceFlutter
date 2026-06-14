/// Triggers a browser/file download of [text] as [filename].
///
/// On web this downloads a real file; on other platforms there's no universal
/// download target, so it returns false and the caller falls back (e.g. copy
/// to clipboard).
library;

export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
