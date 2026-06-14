import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mobile/desktop: load the public form page in a WebView.
class FormViewer extends StatefulWidget {
  const FormViewer({super.key, required this.url});
  final String url;

  @override
  State<FormViewer> createState() => _FormViewerState();
}

class _FormViewerState extends State<FormViewer> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
