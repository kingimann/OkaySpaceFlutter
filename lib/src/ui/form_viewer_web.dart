import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

int _seq = 0;

/// Web: embed the (frameable) public form page in an iframe platform view.
class FormViewer extends StatefulWidget {
  const FormViewer({super.key, required this.url});
  final String url;

  @override
  State<FormViewer> createState() => _FormViewerState();
}

class _FormViewerState extends State<FormViewer> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'form-iframe-${_seq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.src = widget.url;
      iframe.style.setProperty('border', 'none');
      iframe.style.setProperty('width', '100%');
      iframe.style.setProperty('height', '100%');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
