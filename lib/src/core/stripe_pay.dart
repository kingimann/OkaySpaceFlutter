import 'stripe_pay_stub.dart' if (dart.library.io) 'stripe_pay_io.dart'
    as impl;

/// Native Stripe PaymentSheet (iOS/Android). The web stub reports
/// unsupported so callers fall back to hosted checkout/payment links.
bool get stripeSheetSupported => impl.supported;

/// Presents the PaymentSheet for [clientSecret]. Returns true when the
/// payment completed, false when the user cancelled. Throws on failure.
Future<bool> stripePaySheet({
  required String publishableKey,
  required String clientSecret,
  String merchantName = 'OkaySpace',
}) =>
    impl.paySheet(
        publishableKey: publishableKey,
        clientSecret: clientSecret,
        merchantName: merchantName);
