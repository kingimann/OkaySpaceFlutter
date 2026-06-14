/// The advanced (Apryse WebViewer) PDF editor view.
///
/// On Flutter web it embeds Apryse WebViewer — which supports true in-place
/// text editing — as a platform view, loading the engine from a CDN so nothing
/// is self-hosted. Native builds don't embed a browser, so they fall back to a
/// notice directing the user to the web app.
library;

export 'pdf_webviewer_stub.dart'
    if (dart.library.html) 'pdf_webviewer_web.dart';
