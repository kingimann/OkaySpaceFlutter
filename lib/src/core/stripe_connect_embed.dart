/// Embedded Stripe Connect components (web-only facade).
///
/// On the web, Stripe's Connect.js renders the account-onboarding /
/// account-management forms inline in the page, fed by the backend's
/// `/payments/payouts/account-session` endpoint. Native builds report
/// unsupported and keep using Stripe's hosted links.
library;

export 'stripe_connect_embed_stub.dart'
    if (dart.library.html) 'stripe_connect_embed_web.dart';
