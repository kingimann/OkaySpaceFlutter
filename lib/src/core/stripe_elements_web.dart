import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the inline Stripe Payment Element: card entry
/// rendered inside the app against a PaymentIntent client secret. Card data
/// goes straight to Stripe's iframe — it never touches the app or backend.
bool get stripeElementsSupported => true;

class StripeElementsHandle {
  const StripeElementsHandle({required this.view, required this.confirm});

  final Widget view;

  /// Confirms the payment; resolves to null on success or an error message.
  final Future<String?> Function() confirm;
}

Completer<void>? _script;

Future<void> _ensureStripeJs() {
  final existing = _script;
  if (existing != null) return existing.future;
  final c = _script = Completer<void>();
  if (!web.window.getProperty('Stripe'.toJS).isUndefinedOrNull) {
    c.complete();
    return c.future;
  }
  final s = web.document.createElement('script') as web.HTMLScriptElement
    ..src = 'https://js.stripe.com/v3'
    ..async = true;
  s.addEventListener(
      'load',
      ((web.Event _) {
        if (c.isCompleted) return;
        web.window.getProperty('Stripe'.toJS).isUndefinedOrNull
            ? c.completeError(StateError('Stripe.js loaded without Stripe'))
            : c.complete();
      }).toJS);
  s.addEventListener(
      'error',
      ((web.Event _) {
        if (!c.isCompleted) {
          c.completeError(StateError('Could not load Stripe.js'));
        }
      }).toJS);
  web.document.head!.appendChild(s);
  return c.future;
}

int _seq = 0;

Future<StripeElementsHandle> createPaymentElement({
  required String publishableKey,
  required String clientSecret,
  bool darkTheme = true,
}) async {
  await _ensureStripeJs();
  final ctor = web.window.getProperty('Stripe'.toJS);
  final stripe =
      (ctor as JSFunction).callAsFunction(null, publishableKey.toJS)
          as JSObject;
  final elements = stripe.callMethod(
      'elements'.toJS,
      {
        'clientSecret': clientSecret,
        'appearance': {'theme': darkTheme ? 'night' : 'stripe'},
      }.jsify()) as JSObject;
  final payEl =
      elements.callMethod('create'.toJS, 'payment'.toJS) as JSObject;

  final viewType = 'stripe-payment-element-${_seq++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final container =
        web.document.createElement('div') as web.HTMLDivElement;
    container.style
      ..width = '100%'
      ..minHeight = '100%'
      ..overflow = 'auto'
      ..padding = '4px';
    payEl.callMethod('mount'.toJS, container);
    return container;
  });

  Future<String?> confirm() async {
    final args = <String, Object?>{}.jsify() as JSObject;
    args.setProperty('elements'.toJS, elements);
    args.setProperty('redirect'.toJS, 'if_required'.toJS);
    final res = await (stripe.callMethod('confirmPayment'.toJS, args)
            as JSPromise)
        .toDart;
    final err =
        res.isUndefinedOrNull ? null : (res as JSObject).getProperty('error'.toJS);
    if (err == null || err.isUndefinedOrNull) return null;
    final msg = (err as JSObject).getProperty('message'.toJS);
    return msg.isUndefinedOrNull
        ? 'The payment could not be completed.'
        : (msg as JSString).toDart;
  }

  return StripeElementsHandle(
      view: HtmlElementView(viewType: viewType), confirm: confirm);
}
