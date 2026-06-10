import 'dart:async';

import 'package:flutter/foundation.dart';

import 'update_checker_stub.dart'
    if (dart.library.html) 'update_checker_web.dart' as impl;

/// The build id this bundle was compiled from. Set at build time via
/// `--dart-define=BUILD_STAMP=...`; falls back to 'dev' for local runs/tests.
const String kBuildStamp =
    String.fromEnvironment('BUILD_STAMP', defaultValue: 'dev');

/// Flips true once a newer build has been deployed while the app is open.
final ValueNotifier<bool> updateAvailable = ValueNotifier<bool>(false);

Timer? _timer;

/// Starts polling the deployed `version.json` and flips [updateAvailable] when
/// the live build differs from this one. No-op off the web or in dev builds.
void startUpdateChecks() {
  if (kBuildStamp == 'dev' || _timer != null) return;
  _check();
  _timer = Timer.periodic(const Duration(minutes: 3), (_) => _check());
}

Future<void> _check() async {
  if (updateAvailable.value) return; // already prompting
  final remote = await impl.fetchRemoteBuild();
  if (remote != null && remote.isNotEmpty && remote != kBuildStamp) {
    updateAvailable.value = true;
  }
}

/// Hard-reloads the app to pick up the new build (web only).
void reloadApp() => impl.reloadApp();
