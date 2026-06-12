import 'package:flutter/widgets.dart';

/// Stub for non-web platforms: embedded Stripe Connect components are
/// web-only (Connect.js); native builds keep the hosted-link flow.
bool get stripeEmbedSupported => false;

Widget stripeConnectView({
  required String publishableKey,
  required Future<String> Function() fetchClientSecret,
  required String component,
  void Function()? onExit,
  void Function(String message)? onError,
}) =>
    const SizedBox.shrink();
