import 'package:flutter/widgets.dart';

/// Stub for non-web platforms: the inline Payment Element is web-only —
/// native builds use the Stripe PaymentSheet instead.
bool get stripeElementsSupported => false;

class StripeElementsHandle {
  const StripeElementsHandle({required this.view, required this.confirm});

  final Widget view;

  /// Confirms the payment; resolves to null on success or an error message.
  final Future<String?> Function() confirm;
}

Future<StripeElementsHandle> createPaymentElement({
  required String publishableKey,
  required String clientSecret,
  bool darkTheme = true,
}) async =>
    throw UnsupportedError('Payment Element is web-only');
