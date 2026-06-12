/// Inline Stripe Payment Element (web-only facade).
///
/// Renders Stripe's card form inside the app against a PaymentIntent client
/// secret — no redirect to stripe.com. Native builds use the PaymentSheet
/// instead (see stripe_pay.dart) and report unsupported here.
library;

export 'stripe_elements_stub.dart'
    if (dart.library.html) 'stripe_elements_web.dart';
