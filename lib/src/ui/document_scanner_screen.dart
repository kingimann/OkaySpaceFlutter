import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'common.dart';

/// Scan documents with the camera, give them a convincing "scanned" look
/// (grayscale / high-contrast B&W with grain), and export a multi-page PDF.
class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  final List<Uint8List> _originals = [];
  final List<Uint8List> _pages = []; // processed, parallel to _originals
  String _mode = 'bw'; // bw | gray | color
  bool _busy = false;

  /// Applies the scanned look to one page's raw bytes.
  static Uint8List _process(Uint8List src, String mode) {
    var im = img.decodeImage(src);
    if (im == null) return src;
    if (im.width > 1654) im = img.copyResize(im, width: 1654); // ~A4 @ 200dpi
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
    im = img.noise(im, 5, type: img.NoiseType.gaussian); // scanner grain
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
      final processed = _process(src, _mode);
      if (mounted) {
        setState(() {
          _originals.add(src);
          _pages.add(processed);
        });
      }
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
    final reprocessed = [for (final o in _originals) _process(o, m)];
    if (mounted) {
      setState(() {
        _mode = m;
        _pages
          ..clear()
          ..addAll(reprocessed);
        _busy = false;
      });
    }
  }

  Future<void> _export() async {
    if (_pages.isEmpty) return;
    setState(() => _busy = true);
    try {
      final doc = pw.Document();
      for (final b in _pages) {
        final image = pw.MemoryImage(b);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ));
      }
      final bytes = await doc.save();
      await Printing.sharePdf(
          bytes: bytes,
          filename: 'scan-${DateTime.now().millisecondsSinceEpoch}.pdf');
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
            TextButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: const Text('PDF'),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: _busy ? null : _addSheet,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(_pages.isEmpty ? 'Add page' : 'Add page'),
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
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => _pageCard(i, scheme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pageCard(int i, ColorScheme scheme) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(_pages[i], fit: BoxFit.cover),
          ),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: Text('${i + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: IconButton(
            icon: const CircleAvatar(
                radius: 14,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 16, color: Colors.white)),
            onPressed: _busy
                ? null
                : () => setState(() {
                      _originals.removeAt(i);
                      _pages.removeAt(i);
                    }),
          ),
        ),
      ],
    );
  }
}
