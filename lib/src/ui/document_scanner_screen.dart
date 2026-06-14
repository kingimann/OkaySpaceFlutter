import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../okayspace_api.dart';
import 'common.dart';

class _ScanPage {
  _ScanPage(this.id, this.original, this.processed);
  final int id;
  final Uint8List original;
  Uint8List processed;
}

/// Scan documents with the camera, give them a convincing "scanned" look
/// (grayscale / high-contrast B&W with grain), reorder/remove pages, and
/// export — or send — a multi-page PDF.
class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  final List<_ScanPage> _pages = [];
  int _seq = 0;
  String _mode = 'bw'; // bw | gray | color
  bool _busy = false;

  static Uint8List _process(Uint8List src, String mode) {
    var im = img.decodeImage(src);
    if (im == null) return src;
    if (im.width > 1654) im = img.copyResize(im, width: 1654);
    if (mode == 'color') {
      im = img.adjustColor(im, contrast: 1.15, brightness: 1.05, saturation: 1.1);
    } else {
      im = img.grayscale(im);
      im = img.adjustColor(im, contrast: 1.5, brightness: 1.08);
      if (mode == 'bw') {
        for (final p in im) {
          final v = p.luminanceNormalized > 0.52 ? 255 : 0;
          p.setRgb(v, v, v);
        }
      }
    }
    im = img.noise(im, 5, type: img.NoiseType.gaussian);
    return img.encodeJpg(im, quality: 82);
  }

  Future<void> _add(ImageSource source) async {
    final f = await ImagePicker()
        .pickImage(source: source, maxWidth: 2400, imageQuality: 95);
    if (f == null) return;
    final src = await f.readAsBytes();
    if (!mounted) return;
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    try {
      final page = _ScanPage(_seq++, src, _process(src, _mode));
      if (mounted) setState(() => _pages.add(page));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Scan with camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source != null) await _add(source);
  }

  Future<void> _setMode(String m) async {
    if (m == _mode || _busy) return;
    setState(() => _busy = true);
    await Future<void>.delayed(Duration.zero);
    for (final p in _pages) {
      p.processed = _process(p.original, m);
    }
    if (mounted) {
      setState(() {
        _mode = m;
        _busy = false;
      });
    }
  }

  Future<Uint8List> _pdfBytes() async {
    final doc = pw.Document();
    for (final p in _pages) {
      final image = pw.MemoryImage(p.processed);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ));
    }
    return doc.save();
  }

  Future<void> _export() async {
    if (_pages.isEmpty) return;
    setState(() => _busy = true);
    try {
      await Printing.sharePdf(
          bytes: await _pdfBytes(),
          filename: 'scan-${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendToChat() async {
    if (_pages.isEmpty) return;
    final conv = await pickConversation(context);
    if (conv == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await _pdfBytes();
      await api.messaging.send(
        conv.id,
        MessageCreate(
          type: 'file',
          fileBase64: base64Encode(bytes),
          fileName: 'scan.pdf',
          fileSize: bytes.length,
          fileMime: 'application/pdf',
        ),
      );
      if (mounted) showInfo(context, 'Sent');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Scan'),
        actions: [
          if (_pages.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.ios_share),
              enabled: !_busy,
              onSelected: (v) => v == 'chat' ? _sendToChat() : _export(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('Save / share PDF')),
                PopupMenuItem(value: 'chat', child: Text('Send to a chat')),
              ],
            ),
        ],
      ),
      floatingActionButton: liftedFab(
        FloatingActionButton.extended(
          onPressed: _busy ? null : _addSheet,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add page'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              for (final (m, label) in const [
                ('bw', 'B&W'),
                ('gray', 'Grayscale'),
                ('color', 'Colour'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _mode == m,
                    onSelected: _busy ? null : (_) => _setMode(m),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ]),
          ),
          if (_pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Drag to reorder',
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
              ),
            ),
          Expanded(
            child: _pages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.document_scanner_outlined,
                            size: 64, color: scheme.outline),
                        const SizedBox(height: 14),
                        const Text('Scan a document',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('Add pages, then export a PDF.',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
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
        leading: Container(
          width: 44,
          height: 56,
          color: Colors.white,
          child: Image.memory(p.processed, fit: BoxFit.cover),
        ),
        title: Text('Page ${i + 1}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () => setState(() => _pages.removeAt(i)),
            ),
            ReorderableDragStartListener(
              index: i,
              child: const Padding(
                  padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
            ),
          ],
        ),
      ),
    );
  }
}
