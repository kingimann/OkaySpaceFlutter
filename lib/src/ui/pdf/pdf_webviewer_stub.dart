import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'pdf_webviewer_controller.dart';

/// Native builds can't host the WebViewer JS engine.
bool get apryseSupported => false;

class ApryseEditorView extends StatelessWidget {
  const ApryseEditorView({
    super.key,
    required this.pdfBytes,
    required this.controller,
  });

  final Uint8List pdfBytes;
  final ApryseController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_document, size: 56, color: scheme.outline),
            const SizedBox(height: 14),
            const Text('Advanced editing runs in the web app',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Open OkaySpace on the web to edit PDF text in place. '
              'The page-level editor here still handles reorder, replace, '
              'forms, redaction and more.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
