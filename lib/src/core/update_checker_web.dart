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

void reloadApp() => html.window.location.reload();
