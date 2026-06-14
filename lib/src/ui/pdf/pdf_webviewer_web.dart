import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'pdf_webviewer_config.dart';
import 'pdf_webviewer_controller.dart';

/// Web supports the embedded Acrobat-grade editor.
bool get apryseSupported => true;

int _seq = 0;

/// Glue installed once on the host page. It wraps WebViewer's promise-based API
/// in two helpers Dart can call: [open] (instantiate + load a PDF + enable
/// in-place content editing) and [save] (return the edited bytes).
const String _glueJs = r'''
(function () {
  if (window.OkWV) return;
  window.OkWV = {
    open: function (el, bytes, opts) {
      return new Promise(function (resolve, reject) {
        if (typeof WebViewer === 'undefined') {
          reject(new Error('WebViewer is not available'));
          return;
        }
        var blob = new Blob([bytes], { type: 'application/pdf' });
        var url = URL.createObjectURL(blob);
        var cfg = {
          path: opts.path,
          fullAPI: true,
          initialDoc: url,
          extension: 'pdf',
          enableFilePicker: false
        };
        if (opts.licenseKey) { cfg.licenseKey = opts.licenseKey; }
        WebViewer(cfg, el).then(function (instance) {
          el.okWvInstance = instance;
          try {
            instance.UI.enableFeatures([instance.UI.Feature.ContentEdit]);
          } catch (e) {}
          resolve(true);
        }).catch(function (err) { reject(err); });
      });
    },
    save: function (el) {
      return new Promise(function (resolve, reject) {
        var instance = el.okWvInstance;
        if (!instance) { reject(new Error('Editor is not ready')); return; }
        var core = instance.Core;
        var doc = core.documentViewer.getDocument();
        core.annotationManager.exportAnnotations().then(function (xfdf) {
          return doc.getFileData({ xfdfString: xfdf });
        }).then(function (data) {
          resolve(new Uint8Array(data));
        }).catch(function (err) { reject(err); });
      });
    }
  };
})();
''';

enum _Status { loading, ready, error }

class ApryseEditorView extends StatefulWidget {
  const ApryseEditorView({
    super.key,
    required this.pdfBytes,
    required this.controller,
  });

  final Uint8List pdfBytes;
  final ApryseController controller;

  @override
  State<ApryseEditorView> createState() => _ApryseEditorViewState();
}

class _ApryseEditorViewState extends State<ApryseEditorView> {
  late final String _viewType;
  web.HTMLDivElement? _div;
  _Status _status = _Status.loading;
  String _err = '';

  @override
  void initState() {
    super.initState();
    widget.controller.onExport = _exportBytes;
    _viewType = 'apryse-wv-${_seq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final div = web.document.createElement('div') as web.HTMLDivElement;
      div.style.setProperty('width', '100%');
      div.style.setProperty('height', '100%');
      _div = div;
      // Boot once the element is attached to the DOM.
      web.window.requestAnimationFrame(((double _) {
        _boot();
      }).toJS);
      return div;
    });
  }

  Future<void> _boot() async {
    try {
      _injectGlue();
      await _ensureWebViewer();
      await _open();
      if (mounted) setState(() => _status = _Status.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _err = '$e';
        });
      }
    }
  }

  void _injectGlue() {
    if (web.document.getElementById('ok-wv-glue') != null) return;
    final s = web.document.createElement('script') as web.HTMLScriptElement;
    s.id = 'ok-wv-glue';
    s.text = _glueJs;
    web.document.head!.appendChild(s);
  }

  /// Loads WebViewer from the CDN (shared across editor instances) and waits
  /// until the global is available.
  Future<void> _ensureWebViewer() async {
    if (globalContext.has('WebViewer')) return;
    if (web.document.getElementById('ok-wv-cdn') == null) {
      final s = web.document.createElement('script') as web.HTMLScriptElement;
      s.id = 'ok-wv-cdn';
      s.src = '$kAprysePath/webviewer.min.js';
      web.document.head!.appendChild(s);
    }
    for (var i = 0; i < 200; i++) {
      if (globalContext.has('WebViewer')) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Could not load WebViewer from $kAprysePath');
  }

  Future<void> _open() async {
    final el = _div;
    if (el == null) throw StateError('No host element');
    final opts = JSObject();
    opts['path'] = kAprysePath.toJS;
    if (kApryseLicenseKey.isNotEmpty) {
      opts['licenseKey'] = kApryseLicenseKey.toJS;
    }
    final okwv = globalContext['OkWV'] as JSObject;
    final promise =
        okwv.callMethod<JSPromise>('open'.toJS, el, widget.pdfBytes.toJS, opts);
    await promise.toDart;
  }

  Future<Uint8List?> _exportBytes() async {
    final el = _div;
    if (el == null || _status != _Status.ready) return null;
    try {
      final okwv = globalContext['OkWV'] as JSObject;
      final promise = okwv.callMethod<JSPromise>('save'.toJS, el);
      final res = await promise.toDart;
      if (res == null) return null;
      return (res as JSUint8Array).toDart;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
      return null;
    }
  }

  @override
  void dispose() {
    widget.controller.onExport = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(child: HtmlElementView(viewType: _viewType)),
        if (_status == _Status.loading)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading the editor…'),
                  ],
                ),
              ),
            ),
          ),
        if (_status == _Status.error)
          Positioned.fill(child: _errorCard(scheme)),
      ],
    );
  }

  Widget _errorCard(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 52, color: scheme.outline),
              const SizedBox(height: 14),
              const Text("Couldn't load the advanced editor",
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'The WebViewer engine is loaded from a CDN. This usually means '
                'the network blocked it, or the editor needs a license key.\n\n'
                'Set one at build time:\n'
                'flutter build web --dart-define=APRYSE_LICENSE_KEY=your_key',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(_err,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
