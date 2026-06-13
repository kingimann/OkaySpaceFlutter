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

class StripeCardTokenHandle {
  const StripeCardTokenHandle({required this.view, required this.tokenize});

  final Widget view;

  /// Tokenizes the entered card; returns (token, null) or (null, error).
  final Future<({String? token, String? error})> Function() tokenize;
}

/// An inline card-entry element (Stripe 'card' Element) for tokenizing a
/// payout debit card in-app — the DoorDash-style flow. The number never
/// touches the app: Stripe's iframe produces a token for the backend.
Future<StripeCardTokenHandle> createCardTokenElement({
  required String publishableKey,
  bool darkTheme = true,
}) async {
  await _ensureStripeJs();
  final ctor = web.window.getProperty('Stripe'.toJS);
  final stripe =
      (ctor as JSFunction).callAsFunction(null, publishableKey.toJS)
          as JSObject;
  final elements =
      stripe.callMethod('elements'.toJS, <String, Object?>{}.jsify())
          as JSObject;
  final card = elements.callMethod(
      'create'.toJS,
      'card'.toJS,
      {
        'style': {
          'base': {
            'color': darkTheme ? '#E7EDF3' : '#1A1A1A',
            'iconColor': darkTheme ? '#8FA3B0' : '#666',
            '::placeholder': {'color': darkTheme ? '#5B6B76' : '#999'},
            'fontSize': '16px',
          },
          'invalid': {'color': '#EF4444'},
        },
        'hidePostalCode': false,
      }.jsify()) as JSObject;

  final viewType = 'stripe-card-element-${_seq++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final container =
        web.document.createElement('div') as web.HTMLDivElement;
    container.style
      ..width = '100%'
      ..padding = '14px 12px'
      ..borderRadius = '12px'
      ..border = '1px solid ${darkTheme ? '#33414C' : '#ddd'}'
      ..background = darkTheme ? '#101A21' : '#fff';
    card.callMethod('mount'.toJS, container);
    return container;
  });

  Future<({String? token, String? error})> tokenize() async {
    final res =
        await (stripe.callMethod('createToken'.toJS, card) as JSPromise)
            .toDart;
    if (res.isUndefinedOrNull) {
      return (token: null, error: 'Tokenization returned nothing.');
    }
    final obj = res as JSObject;
    final err = obj.getProperty('error'.toJS);
    if (err != null && !err.isUndefinedOrNull) {
      final msg = (err as JSObject).getProperty('message'.toJS);
      return (
        token: null,
        error: msg.isUndefinedOrNull
            ? 'The card could not be tokenized.'
            : (msg as JSString).toDart
      );
    }
    final token = obj.getProperty('token'.toJS);
    final id = token.isUndefinedOrNull
        ? null
        : (token as JSObject).getProperty('id'.toJS);
    return id == null || id.isUndefinedOrNull
        ? (token: null, error: 'No token id in Stripe\'s reply.')
        : (token: (id as JSString).toDart, error: null);
  }

  return StripeCardTokenHandle(
      view: SizedBox(height: 52, child: HtmlElementView(viewType: viewType)),
      tokenize: tokenize);
}

/// Stripe Identity verification as an in-page modal (no redirect). Returns
/// null on success/closed, or an error message. Requires the verification
/// session's client secret.
Future<String?> stripeVerifyIdentityModal({
  required String publishableKey,
  required String clientSecret,
}) async {
  await _ensureStripeJs();
  final ctor = web.window.getProperty('Stripe'.toJS);
  final stripe =
      (ctor as JSFunction).callAsFunction(null, publishableKey.toJS)
          as JSObject;
  final res = await (stripe.callMethod(
          'verifyIdentity'.toJS, clientSecret.toJS) as JSPromise)
      .toDart;
  if (res.isUndefinedOrNull) return null;
  final err = (res as JSObject).getProperty('error'.toJS);
  if (err == null || err.isUndefinedOrNull) return null;
  final msg = (err as JSObject).getProperty('message'.toJS);
  return msg.isUndefinedOrNull
      ? 'Verification could not start.'
      : (msg as JSString).toDart;
}

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
