/// Non-web fallback: there's no deployed version.json to check, and nothing to
/// reload, so both operations are no-ops.
Future<String?> fetchRemoteBuild() async => null;

void reloadApp() {}
