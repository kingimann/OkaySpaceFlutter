import 'package:flutter_stripe/flutter_stripe.dart';

bool get supported => true;

Future<bool> paySheet({
  required String publishableKey,
  required String clientSecret,
  String merchantName = 'OkaySpace',
}) async {
  if (Stripe.publishableKey != publishableKey) {
    Stripe.publishableKey = publishableKey;
    await Stripe.instance.applySettings();
  }
  await Stripe.instance.initPaymentSheet(
    paymentSheetParameters: SetupPaymentSheetParameters(
      paymentIntentClientSecret: clientSecret,
      merchantDisplayName: merchantName,
    ),
  );
  try {
    await Stripe.instance.presentPaymentSheet();
    return true;
  } on StripeException catch (e) {
    if (e.error.code == FailureCode.Canceled) return false;
    rethrow;
  }
}
