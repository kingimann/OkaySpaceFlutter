import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the embedded Stripe Connect components
/// (account onboarding / account management) via Connect.js.
bool get stripeEmbedSupported => true;

Completer<void>? _script;

bool get _connectReady {
  final sc = web.window.getProperty('StripeConnect'.toJS);
  if (sc.isUndefinedOrNull) return false;
  return !(sc as JSObject).getProperty('init'.toJS).isUndefinedOrNull;
}

/// Loads Connect.js once. Stripe's manual-include contract: create
/// `window.StripeConnect` and set `onload` BEFORE the script runs.
Future<void> _ensureConnectJs() {
  final existing = _script;
  if (existing != null) return existing.future;
  final c = _script = Completer<void>();
  if (_connectReady) {
    c.complete();
    return c.future;
  }
  final holder = <String, Object?>{}.jsify() as JSObject;
  holder.setProperty(
      'onload'.toJS,
      (() {
        if (!c.isCompleted) c.complete();
      }).toJS);
  web.window.setProperty('StripeConnect'.toJS, holder);
  final s =
      web.document.createElement('script') as web.HTMLScriptElement
        ..src = 'https://connect.stripe.com/v1.0/connect.js'
        ..async = true;
  s.addEventListener(
      'error',
      ((web.Event _) {
        if (!c.isCompleted) {
          c.completeError(StateError('Could not load Stripe Connect.js'));
        }
      }).toJS);
  s.addEventListener(
      'load',
      ((web.Event _) {
        // Some load paths have init available before onload fires.
        if (!c.isCompleted && _connectReady) c.complete();
      }).toJS);
  web.document.head!.appendChild(s);
  return c.future;
}

int _viewSeq = 0;

/// An embedded Stripe Connect component ([component] is e.g.
/// 'account-onboarding' or 'account-management') rendered in-page.
/// [onError] fires when the script, init, or component fails so the caller
/// can fall back to Stripe's hosted link.
Widget stripeConnectView({
  required String publishableKey,
  required Future<String> Function() fetchClientSecret,
  required String component,
  String? fallbackComponent,
  void Function()? onExit,
  void Function(String message)? onError,
}) {
  final viewType = 'stripe-connect-$component-${_viewSeq++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final container =
        web.document.createElement('div') as web.HTMLDivElement;
    container.style
      ..width = '100%'
      ..height = '100%'
      ..overflow = 'auto'
      ..background = '#ffffff';
    // Visible while Connect.js boots; replaced by the Stripe component.
    final loading = web.document.createElement('div') as web.HTMLDivElement;
    loading.textContent = 'Loading secure Stripe form…';
    loading.style
      ..padding = '24px'
      ..color = '#555'
      ..fontFamily = 'sans-serif';
    container.appendChild(loading);
    () async {
      try {
        await _ensureConnectJs();
        final sc =
            web.window.getProperty('StripeConnect'.toJS) as JSObject;
        final args = <String, Object?>{}.jsify() as JSObject;
        args.setProperty('publishableKey'.toJS, publishableKey.toJS);
        args.setProperty(
            'fetchClientSecret'.toJS,
            (() => fetchClientSecret().then((s) => s.toJS).toJS).toJS);
        final instance = sc.callMethod('init'.toJS, args) as JSObject;
        // The account session controls which components are enabled; fall
        // back (e.g. account-management → account-onboarding) before failing.
        JSObject? el;
        for (final name in <String>[
          component,
          if (fallbackComponent != null) fallbackComponent
        ]) {
          try {
            final created = instance.callMethod('create'.toJS, name.toJS);
            if (created != null && !created.isUndefinedOrNull) {
              el = created as JSObject;
              break;
            }
          } catch (_) {/* try the fallback component */}
        }
        if (el == null) {
          throw StateError(
              'Stripe could not create the "$component" component — the '
              'account session may not have it enabled.');
        }
        final done = onExit;
        if (done != null &&
            !el.getProperty('setOnExit'.toJS).isUndefinedOrNull) {
          el.callMethod('setOnExit'.toJS, (() => done()).toJS);
        }
        loading.remove();
        container.appendChild(el as web.Node);
      } catch (e) {
        loading.remove();
        onError?.call('$e');
      }
    }();
    return container;
  });
  return HtmlElementView(viewType: viewType);
}
