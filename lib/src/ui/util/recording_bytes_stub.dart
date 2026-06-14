import 'dart:io';
import 'dart:typed_data';

/// Native: the recording is a file on disk.
Future<Uint8List?> readRecording(String pathOrUrl) async {
  try {
    return await File(pathOrUrl).readAsBytes();
  } catch (_) {
    return null;
  }
}
