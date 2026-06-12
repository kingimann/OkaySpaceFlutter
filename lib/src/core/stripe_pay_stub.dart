/// Web/unsupported: no native PaymentSheet — use hosted checkout instead.
bool get supported => false;

Future<bool> paySheet({
  required String publishableKey,
  required String clientSecret,
  String merchantName = 'OkaySpace',
}) async =>
    false;
