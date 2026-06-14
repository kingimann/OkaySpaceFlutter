import 'dart:typed_data';

/// Bridges the host UI (an AppBar "Apply" button) to the embedded WebViewer
/// instance. The platform-specific [ApryseEditorView] registers [onExport] in
/// its initState; calling [export] pulls the edited PDF bytes back out.
class ApryseController {
  Future<Uint8List?> Function()? onExport;

  /// Returns the current document's edited bytes, or null if unavailable.
  Future<Uint8List?> export() async {
    final fn = onExport;
    if (fn == null) return null;
    return fn();
  }
}
