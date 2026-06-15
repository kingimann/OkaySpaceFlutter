import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'http_transport.dart';
import 'update_checker_stub.dart'
    if (dart.library.html) 'update_checker_web.dart' as impl;

/// The build id this bundle was compiled from. Set at build time via
/// `--dart-define=BUILD_STAMP=...`; falls back to 'dev' for local runs/tests.
const String kBuildStamp =
    String.fromEnvironment('BUILD_STAMP', defaultValue: 'dev');

/// Flips true once a newer build has been deployed while the app is open.
final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);

/// Server-controlled flag: phone browsers should be nudged toward the
/// native app (admin → mobile-web gate). Read from /public/app-config.
final ValueNotifier<bool> mobileWebGate = ValueNotifier<bool>(false);

/// Server-controlled registration mode: 'open' | 'invite' | 'closed'.
/// Read from /public/app-config so the sign-up screen can adapt.
final ValueNotifier<String> registrationMode =
    ValueNotifier<String>('open');

/// Whether the backend encrypts message content at rest (MESSAGE_ENC_KEY set).
/// Drives the "encrypted" indicator in chats. Read from /public/app-config.
final ValueNotifier<bool> messagesEncrypted = ValueNotifier<bool>(false);

Timer? _timer;
String? _killToken;

/// Starts polling the deployed `version.json` and flips [updateAvailable] when
/// the live build differs from this one. No-op off the web or in dev builds.
void startUpdateChecks() {
  if (kBuildStamp == 'dev' || _timer != null) return;
  _check();
  _timer = Timer.periodic(const Duration(minutes: 3), (_) => _check());
  // Also re-check the moment the user returns to the tab, so a freshly shipped
  // build is picked up right away instead of up to 3 minutes later.
  impl.onForeground(_check);
}

Future<void> _check() async {
  await _checkServerConfig();
  if (updateAvailable.value) return; // already prompting
  final remote = await impl.fetchRemoteBuild();
  if (remote != null && remote.isNotEmpty && remote != kBuildStamp) {
    updateAvailable.value = true;
  }
}

/// Polls the backend's public app-config: the web-update kill-switch token
/// (admin "Force web update" bumps it → open tabs prompt to reload) and the
/// mobile-web gate flag.
Future<void> _checkServerConfig() async {
  try {
    final res = await sendHttp(HttpRequestData(
      method: 'GET',
      url: Uri.parse('${ApiConfig.productionV1}/public/app-config'),
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 15),
    ));
    if (res.status >= 400 || res.body.isEmpty) return;
    final data = jsonDecode(res.body);
    if (data is! Map) return;
    final token = '${data['web_build'] ?? ''}';
    if (token.isNotEmpty) {
      // First sighting is the baseline; a later change means the admin
      // forced an update (or a deploy landed).
      if (_killToken == null) {
        _killToken = token;
      } else if (_killToken != token) {
        updateAvailable.value = true;
      }
    }
    mobileWebGate.value = data['mobile_web_gate'] == true;
    messagesEncrypted.value = data['messages_encrypted'] == true;
    final mode = '${data['registration_mode'] ?? 'open'}'.toLowerCase();
    if (const ['open', 'invite', 'closed'].contains(mode)) {
      registrationMode.value = mode;
    }
  } catch (_) {/* offline — try again next tick */}
}

/// Hard-reloads the app to pick up the new build (web only).
void reloadApp() => impl.reloadApp();
