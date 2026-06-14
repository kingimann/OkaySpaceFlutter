/// An in-app form viewer: an iframe on web, a WebView on mobile.
library;

export 'form_viewer_io.dart' if (dart.library.html) 'form_viewer_web.dart';
