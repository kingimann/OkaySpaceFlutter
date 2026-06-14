/// A WebGL (Three.js) game rendered in-app.
///
/// On Flutter web the game runs inside a sandboxed `<iframe>` (a platform view)
/// and reports its final score back over `postMessage`. Native builds don't
/// embed a browser, so they fall back to a small notice.
library;

export 'three_game_stub.dart'
    if (dart.library.html) 'three_game_web.dart';
