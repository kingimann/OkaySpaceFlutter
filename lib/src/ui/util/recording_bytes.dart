/// Reads the bytes of a finished recording from the path/URL that the `record`
/// package returns from `stop()` (a file path on native, a blob URL on web).
library;

export 'recording_bytes_stub.dart'
    if (dart.library.html) 'recording_bytes_web.dart';
