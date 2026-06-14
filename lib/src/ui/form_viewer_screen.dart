import 'package:flutter/material.dart';

import 'common.dart';
import 'form_viewer.dart';

/// Opens a form inside the app (rather than an external browser).
class FormViewerScreen extends StatelessWidget {
  const FormViewerScreen({super.key, required this.url, this.title = 'Form'});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(title: Text(title)),
      body: FormViewer(url: url),
    );
  }
}
