import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../common.dart';
import 'pdf_webviewer.dart';
import 'pdf_webviewer_controller.dart';

/// Full-screen Acrobat-grade editor (Apryse WebViewer). Edit text in place,
/// then "Apply" to hand the edited bytes back to the page-level editor.
class ApryseEditorScreen extends StatefulWidget {
  const ApryseEditorScreen({super.key, required this.pdfBytes});
  final Uint8List pdfBytes;

  @override
  State<ApryseEditorScreen> createState() => _ApryseEditorScreenState();
}

class _ApryseEditorScreenState extends State<ApryseEditorScreen> {
  final _controller = ApryseController();
  bool _busy = false;

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final bytes = await _controller.export();
      if (!mounted) return;
      if (bytes == null) {
        showInfo(context, 'Nothing to apply yet');
        return;
      }
      Navigator.pop(context, bytes);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Advanced editor'),
        actions: [
          if (apryseSupported)
            _busy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(
                    onPressed: _apply, child: const Text('Apply')),
        ],
      ),
      body: ApryseEditorView(
        pdfBytes: widget.pdfBytes,
        controller: _controller,
      ),
    );
  }
}
