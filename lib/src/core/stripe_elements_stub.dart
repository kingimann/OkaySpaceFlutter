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

class StripeCardTokenHandle {
  const StripeCardTokenHandle({required this.view, required this.tokenize});

  final Widget view;

  /// Tokenizes the entered card; returns (token, null) or (null, error).
  final Future<({String? token, String? error})> Function() tokenize;
}

Future<StripeCardTokenHandle> createCardTokenElement({
  required String publishableKey,
  bool darkTheme = true,
}) async =>
    throw UnsupportedError('Card Element is web-only');

Future<String?> stripeVerifyIdentityModal({
  required String publishableKey,
  required String clientSecret,
}) async =>
    'Identity modal is web-only';
