import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'common.dart';

class _Anno {
  _Anno(this.rel, this.text, this.size);
  Offset rel; // position as a fraction (0..1) of the page
  String text;
  double size; // font size as a fraction of page width
}

class _Page {
  _Page(this.id, this.png, this.aspect);
  final int id;
  final Uint8List png; // rendered page image
  final double aspect; // width / height
  int quarter = 0; // rotation in quarter-turns
  final List<_Anno> annos = [];
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
  Uint8List? _originalPdf; // source bytes, for real text find/replace
  int _seq = 0;
  bool _busy = false;
  String _status = '';

  Future<void> _openPdf() async {
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    if (!mounted) return;
    _originalPdf = bytes;
    setState(() {
      _busy = true;
      _status = 'Reading PDF…';
    });
    try {
      final added = <_Page>[];
      await for (final page in Printing.raster(bytes, dpi: 150)) {
        final aspect = page.height == 0 ? 0.7071 : page.width / page.height;
        added.add(_Page(_seq++, await page.toPng(), aspect));
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
    final im = img.decodeImage(bytes);
    final aspect = (im == null || im.height == 0) ? 0.7071 : im.width / im.height;
    if (mounted) setState(() => _pages.add(_Page(_seq++, bytes, aspect)));
  }

  Future<void> _promptFindReplace() async {
    final find = TextEditingController();
    final repl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit text'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Find text in the document and replace it.',
                style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 8),
          TextField(
              controller: find,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Find')),
          TextField(
              controller: repl,
              decoration: const InputDecoration(labelText: 'Replace with')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace')),
        ],
      ),
    );
    final f = find.text;
    final r = repl.text;
    find.dispose();
    repl.dispose();
    if (ok == true && f.isNotEmpty) await _findReplace(f, r);
  }

  /// Real text edit: find occurrences in the source PDF, cover them and draw
  /// the replacement, then re-render the pages from the edited document.
  Future<void> _findReplace(String find, String replace) async {
    final src = _originalPdf;
    if (src == null) return;
    setState(() {
      _busy = true;
      _status = 'Editing text…';
    });
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final matches = sf.PdfTextExtractor(doc).findText([find]);
      for (final m in matches) {
        final page = doc.pages[m.pageIndex];
        final b = m.bounds;
        page.graphics.drawRectangle(
            brush: sf.PdfSolidBrush(sf.PdfColor(255, 255, 255)), bounds: b);
        if (replace.isNotEmpty) {
          page.graphics.drawString(
            replace,
            sf.PdfStandardFont(sf.PdfFontFamily.helvetica,
                (b.height * 0.7).clamp(6.0, 72.0).toDouble()),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
            bounds: b,
          );
        }
      }
      final out = Uint8List.fromList(await doc.save());
      doc.dispose();
      _originalPdf = out;
      final rebuilt = <_Page>[];
      await for (final pg in Printing.raster(out, dpi: 150)) {
        final aspect = pg.height == 0 ? 0.7071 : pg.width / pg.height;
        rebuilt.add(_Page(_seq++, await pg.toPng(), aspect));
      }
      if (mounted) {
        setState(() => _pages
          ..clear()
          ..addAll(rebuilt));
        showInfo(
            context,
            matches.isEmpty
                ? 'No matches found'
                : 'Replaced ${matches.length} occurrence(s)');
      }
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
        final rotated = (p.quarter % 4) == 1 || (p.quarter % 4) == 3;
        final aspect = rotated ? 1 / p.aspect : p.aspect;
        const pageW = 595.0; // A4 width in points
        final pageH = pageW / (aspect <= 0 ? 0.7071 : aspect);
        final image = pw.MemoryImage(_rotated(p));
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(pageW, pageH),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(children: [
            pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
            for (final a in p.annos)
              pw.Positioned(
                left: a.rel.dx * pageW,
                top: a.rel.dy * pageH,
                child: pw.Text(a.text,
                    style: pw.TextStyle(
                        fontSize: a.size * pageW, color: PdfColors.black)),
              ),
          ]),
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
          if (_originalPdf != null)
            TextButton.icon(
              onPressed: _busy ? null : _promptFindReplace,
              icon: const Icon(Icons.edit_note, size: 20),
              label: const Text('Edit text'),
            ),
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
              icon: const Icon(Icons.text_fields),
              tooltip: 'Add text',
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _AnnotateScreen(page: p)));
                if (mounted) setState(() {});
              },
            ),
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

/// Place and edit text overlays on a single page; changes are written back to
/// the page's annotation list and burned into the exported PDF.
class _AnnotateScreen extends StatefulWidget {
  const _AnnotateScreen({required this.page});
  final _Page page;

  @override
  State<_AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends State<_AnnotateScreen> {
  _Page get _p => widget.page;

  Future<void> _editAnno(_Anno a) async {
    final controller = TextEditingController(text: a.text);
    var size = a.size;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Text'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Type text…'),
              ),
              Row(children: [
                const Text('Size'),
                Expanded(
                  child: Slider(
                    value: size,
                    min: 0.02,
                    max: 0.12,
                    onChanged: (v) => setLocal(() => size = v),
                  ),
                ),
              ]),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, '__delete__'),
                child: const Text('Delete')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Done')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      if (result == '__delete__') {
        _p.annos.remove(a);
      } else {
        a.text = result;
        a.size = size;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Add text'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final a = _Anno(const Offset(0.3, 0.4), 'Text', 0.045);
          setState(() => _p.annos.add(a));
          _editAnno(a);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add text'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AspectRatio(
            aspectRatio: _p.aspect <= 0 ? 0.7071 : _p.aspect,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth, h = c.maxHeight;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: Colors.white,
                        child: Image.memory(_p.png, fit: BoxFit.fill),
                      ),
                    ),
                    for (final a in _p.annos)
                      Positioned(
                        left: a.rel.dx * w,
                        top: a.rel.dy * h,
                        child: GestureDetector(
                          onTap: () => _editAnno(a),
                          onPanUpdate: (d) => setState(() {
                            a.rel = Offset(
                              (a.rel.dx + d.delta.dx / w).clamp(0.0, 0.98),
                              (a.rel.dy + d.delta.dy / h).clamp(0.0, 0.98),
                            );
                          }),
                          child: Container(
                            color: Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              a.text.isEmpty ? ' ' : a.text,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: a.size * w,
                                  height: 1.0),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
