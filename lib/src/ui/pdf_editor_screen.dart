import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'common.dart';

class _Page {
  _Page(this.id, this.png);
  final int id;
  final Uint8List png; // rendered page image
  int quarter = 0; // rotation in quarter-turns
}

/// A page-level PDF editor: open a PDF (its pages are rendered to images),
/// then reorder, rotate, delete, or add image pages, and export a new PDF.
class PdfEditorScreen extends StatefulWidget {
  const PdfEditorScreen({super.key});

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  final List<_Page> _pages = [];
  int _seq = 0;
  bool _busy = false;
  String _status = '';

  Future<void> _openPdf() async {
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = 'Reading PDF…';
    });
    try {
      final added = <_Page>[];
      await for (final page in Printing.raster(bytes, dpi: 150)) {
        added.add(_Page(_seq++, await page.toPng()));
        if (mounted) {
          setState(() => _status = 'Rendered ${added.length} page(s)…');
        }
      }
      if (mounted) setState(() => _pages.addAll(added));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _addImage() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 92);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) setState(() => _pages.add(_Page(_seq++, bytes)));
  }

  static Uint8List _rotated(_Page p) {
    if (p.quarter % 4 == 0) return p.png;
    final im = img.decodeImage(p.png);
    if (im == null) return p.png;
    return img.encodePng(img.copyRotate(im, angle: (p.quarter % 4) * 90));
  }

  Future<void> _export() async {
    if (_pages.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Building PDF…';
    });
    try {
      final doc = pw.Document();
      for (final p in _pages) {
        final image = pw.MemoryImage(_rotated(p));
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(12),
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ));
      }
      final out = await doc.save();
      await Printing.sharePdf(
          bytes: out, filename: 'edited-${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('PDF editor'),
        actions: [
          IconButton(
            tooltip: 'Add image page',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _busy ? null : _addImage,
          ),
          if (_pages.isNotEmpty)
            TextButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.ios_share, size: 20),
              label: const Text('Export'),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: _busy ? null : _openPdf,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Open PDF'),
        ),
      ),
      body: _busy && _pages.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_status, style: TextStyle(color: scheme.outline)),
              ]),
            )
          : _pages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined,
                          size: 64, color: scheme.outline),
                      const SizedBox(height: 14),
                      const Text('Open a PDF to edit',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('Reorder, rotate, delete or add pages.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_status.isNotEmpty)
                      LinearProgressIndicator(
                          minHeight: 2, backgroundColor: scheme.surface),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: _pages.length,
                        onReorder: (oldI, newI) => setState(() {
                          if (newI > oldI) newI -= 1;
                          _pages.insert(newI, _pages.removeAt(oldI));
                        }),
                        itemBuilder: (_, i) => _pageRow(i, scheme),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _pageRow(int i, ColorScheme scheme) {
    final p = _pages[i];
    return Card(
      key: ValueKey(p.id),
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        leading: SizedBox(
          width: 44,
          height: 56,
          child: RotatedBox(
            quarterTurns: p.quarter % 4,
            child: Image.memory(p.png, fit: BoxFit.contain),
          ),
        ),
        title: Text('Page ${i + 1}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.rotate_right),
              tooltip: 'Rotate',
              onPressed: () => setState(() => p.quarter += 1),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => setState(() => _pages.removeAt(i)),
            ),
            ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
