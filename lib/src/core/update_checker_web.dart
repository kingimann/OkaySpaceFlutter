// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

/// Fetches the deployed build id from version.json (cache-busted). Returns null
/// on any error. The relative URL resolves against the page's <base href>.
Future<String?> fetchRemoteBuild() async {
  try {
    final url = 'version.json?ts=${DateTime.now().millisecondsSinceEpoch}';
    final text = await html.HttpRequest.getString(url);
    final data = jsonDecode(text);
    if (data is Map && data['build'] is String) return data['build'] as String;
  } catch (_) {/* offline or not deployed yet */}
  return null;
}

/// Forces a truly fresh load: clears the Cache Storage and unregisters any
/// service worker (a stale one can otherwise answer the reload from cache and
/// serve the old bundle again), then reloads.
void reloadApp() {
  _purgeCachesAndReload();
}

Future<void> _purgeCachesAndReload() async {
  try {
    final caches = html.window.caches;
    if (caches != null) {
      final keys = await caches.keys();
      for (final k in keys) {
        await caches.delete(k);
      }
    }
  } catch (_) {/* best effort */}
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        await r.unregister();
      }
    }
  } catch (_) {/* best effort */}
  html.window.location.reload();
}
