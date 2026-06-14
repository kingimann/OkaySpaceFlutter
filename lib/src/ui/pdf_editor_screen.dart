import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'common.dart';
import 'pdf/pdf_webviewer.dart' show apryseSupported;
import 'pdf/pdf_webviewer_screen.dart';

class _Anno {
  _Anno(this.rel, this.text, this.size);
  Offset rel; // position as a fraction (0..1) of the page
  String text;
  double size; // font size as a fraction of page width
}

/// A placed image (e.g. a signature) on a page.
class _ImgAnno {
  _ImgAnno(this.rel, this.width, this.png);
  Offset rel; // top-left as a fraction (0..1) of the page
  double width; // width as a fraction of page width
  final Uint8List png;
}

class _Page {
  _Page(this.id, this.png, this.aspect, [this.pdfPageIndex = -1]);
  final int id;
  final Uint8List png; // rendered page image
  final double aspect; // width / height
  final int pdfPageIndex; // index in the source PDF, or -1 (image/merged)
  int quarter = 0; // rotation in quarter-turns
  final List<_Anno> annos = [];
  final List<_ImgAnno> imgs = [];
}

/// A word extracted from the PDF with its bounds (in PDF points) and its
/// position as a fraction of the page (for tap selection).
class _Word {
  _Word(this.text, this.pdf, this.rel, this.fontSize, this.bold, this.italic);
  final String text;
  final Rect pdf;
  final Rect rel;
  final double fontSize; // matches the source, so replacements look the same
  final bool bold;
  final bool italic;
}

/// A select-and-edit operation on a page's words.
/// [mode] is 'replace' (cover + redraw [text]), 'highlight' (translucent
/// yellow marker), or 'redact' (opaque black box).
class _TextEdit {
  _TextEdit(this.pageIndex, this.clear, this.draw, this.text, this.fontSize,
      this.bold, this.italic,
      {this.mode = 'replace'});
  final int pageIndex;
  final List<Rect> clear;
  final Rect draw;
  final String text;
  final double fontSize;
  final bool bold;
  final bool italic;
  final String mode;
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
        added.add(_Page(_seq++, await page.toPng(), aspect, added.length));
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

  /// Appends another PDF's pages to the current document.
  Future<void> _mergePdf() async {
    final res = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Merging…';
    });
    try {
      await for (final pg in Printing.raster(bytes, dpi: 150)) {
        final aspect = pg.height == 0 ? 0.7071 : pg.width / pg.height;
        final page = _Page(_seq++, await pg.toPng(), aspect);
        if (mounted) setState(() => _pages.add(page));
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

  /// Adopt edited PDF bytes and re-render the page previews.
  Future<void> _applyEditedPdf(Uint8List out) async {
    _originalPdf = out;
    final rebuilt = <_Page>[];
    await for (final pg in Printing.raster(out, dpi: 150)) {
      final aspect = pg.height == 0 ? 0.7071 : pg.width / pg.height;
      rebuilt.add(_Page(_seq++, await pg.toPng(), aspect, rebuilt.length));
    }
    if (mounted) {
      setState(() => _pages
        ..clear()
        ..addAll(rebuilt));
    }
  }

  /// Opens a single page to edit; the page screen returns the chosen action.
  Future<void> _openPage(_Page p, int number) async {
    final action = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => _PageScreen(page: p, pageNumber: number)));
    if (!mounted) return;
    switch (action) {
      case 'editText':
        await _editPageText(p);
      case 'find':
        await _promptFindReplace();
      case 'markup':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => _AnnotateScreen(page: p)));
        if (mounted) setState(() {});
      case 'form':
        await _fillForm();
      case 'extract':
        await _extractText();
      case 'duplicate':
        _duplicatePage(p);
      case 'blankAfter':
        _insertBlankAfter(p);
      case 'exportPage':
        await _exportPage(p);
      default:
        setState(() {}); // reflect any rotation done on the page
    }
  }

  /// Extracts the words on a page and opens the select-and-replace editor.
  Future<void> _editPageText(_Page page) async {
    final src = _originalPdf;
    if (src == null) return;
    if (page.pdfPageIndex < 0) {
      showInfo(context, 'Text editing isn\'t available for added/merged pages');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Reading text…';
    });
    final words = <_Word>[];
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final idx = page.pdfPageIndex;
      final size = doc.pages[idx].size;
      final lines = sf.PdfTextExtractor(doc)
          .extractTextLines(startPageIndex: idx, endPageIndex: idx);
      for (final line in lines) {
        final styles = line.fontStyle;
        final bold = styles.contains(sf.PdfFontStyle.bold);
        final italic = styles.contains(sf.PdfFontStyle.italic);
        for (final wd in line.wordCollection) {
          if (wd.text.trim().isEmpty) continue;
          final b = wd.bounds;
          final fontSize =
              line.fontSize > 0 ? line.fontSize : (b.height * 0.85);
          words.add(_Word(
            wd.text,
            b,
            Rect.fromLTWH(b.left / size.width, b.top / size.height,
                b.width / size.width, b.height / size.height),
            fontSize,
            bold,
            italic,
          ));
        }
      }
      doc.dispose();
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
    if (!mounted) return;
    if (words.isEmpty) {
      showInfo(context, 'No selectable text on this page');
      return;
    }
    final edit = await Navigator.of(context).push<_TextEdit>(MaterialPageRoute(
      builder: (_) => _TextSelectScreen(
          pageImage: page.png,
          aspect: page.aspect,
          pageIndex: page.pdfPageIndex,
          words: words),
    ));
    if (edit != null) await _applyTextEdit(edit);
  }

  Future<void> _applyTextEdit(_TextEdit edit) async {
    final src = _originalPdf;
    if (src == null) return;
    if (edit.mode == 'redact') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Redact text'),
          content: const Text(
              'This permanently removes the selected text. To guarantee it '
              'can\'t be recovered, the document\'s selectable text layer is '
              'flattened to an image — find, replace and extract will no longer '
              'work afterwards. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Redact')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _status = 'Replacing…';
    });
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final page = doc.pages[edit.pageIndex];
      if (edit.mode == 'highlight') {
        final g = page.graphics;
        g.save();
        g.setTransparency(0.4);
        for (final r in edit.clear) {
          g.drawRectangle(
              brush: sf.PdfSolidBrush(sf.PdfColor(255, 235, 59)), bounds: r);
        }
        g.restore();
      } else if (edit.mode == 'redact') {
        for (final r in edit.clear) {
          page.graphics.drawRectangle(
              brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)), bounds: r);
        }
      } else {
        for (final r in edit.clear) {
          page.graphics.drawRectangle(
              brush: sf.PdfSolidBrush(sf.PdfColor(255, 255, 255)), bounds: r);
        }
        if (edit.text.isNotEmpty) {
          final styles = <sf.PdfFontStyle>[
            if (edit.bold) sf.PdfFontStyle.bold,
            if (edit.italic) sf.PdfFontStyle.italic,
          ];
          page.graphics.drawString(
            edit.text,
            sf.PdfStandardFont(
              sf.PdfFontFamily.helvetica,
              edit.fontSize.clamp(6.0, 72.0).toDouble(),
              multiStyle: styles.isEmpty ? null : styles,
            ),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
            bounds: edit.draw,
          );
        }
      }
      final outBytes = Uint8List.fromList(await doc.save());
      doc.dispose();
      await _applyEditedPdf(outBytes);
      if (edit.mode == 'redact') {
        // The black box now shows in the re-rendered page images. Replace the
        // working PDF with a flattened, image-only copy so the covered text is
        // truly gone (no recoverable text layer, and Extract returns nothing).
        final flat = await _imagesToPdf();
        if (mounted) _originalPdf = flat;
      }
      if (mounted) {
        showInfo(
            context,
            edit.mode == 'highlight'
                ? 'Highlighted'
                : edit.mode == 'redact'
                    ? 'Redacted'
                    : 'Replaced');
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

  Future<void> _promptFindReplace() async {
    final find = TextEditingController();
    final repl = TextEditingController();
    var review = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit text'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: find,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Find')),
            TextField(
                controller: repl,
                decoration: const InputDecoration(labelText: 'Replace with')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Review each match'),
              subtitle: const Text('Otherwise replace all'),
              value: review,
              onChanged: (v) => setLocal(() => review = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue')),
          ],
        ),
      ),
    );
    final f = find.text;
    final r = repl.text;
    find.dispose();
    repl.dispose();
    if (ok != true || f.isEmpty) return;
    if (!review) {
      await _findReplace(f, r);
      return;
    }
    final matches = await _collectMatches(f);
    if (!mounted) return;
    if (matches.isEmpty) {
      showInfo(context, 'No matches found');
      return;
    }
    final selected = await Navigator.of(context).push<Set<int>>(
        MaterialPageRoute(
            builder: (_) => _ReviewScreen(
                matches: matches, pageImage: (i) => _pages[i].png)));
    if (selected != null && selected.isNotEmpty) {
      await _findReplace(f, r, only: selected);
    }
  }

  /// Locates matches and maps each to a page index + relative bounds, for the
  /// review screen's highlight.
  Future<List<_Match>> _collectMatches(String find) async {
    final src = _originalPdf;
    if (src == null) return [];
    setState(() {
      _busy = true;
      _status = 'Searching…';
    });
    final out = <_Match>[];
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final found = sf.PdfTextExtractor(doc).findText([find]);
      for (final m in found) {
        final size = doc.pages[m.pageIndex].size;
        final b = m.bounds;
        final aspect = (m.pageIndex < _pages.length)
            ? _pages[m.pageIndex].aspect
            : (size.height == 0 ? 0.7071 : size.width / size.height);
        out.add(_Match(
          m.pageIndex,
          Rect.fromLTWH(b.left / size.width, b.top / size.height,
              b.width / size.width, b.height / size.height),
          aspect,
        ));
      }
      doc.dispose();
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
    return out;
  }

  /// Real text edit: cover matched text and draw the replacement. [only] picks
  /// specific match indices (from the review screen); null = replace all.
  Future<void> _findReplace(String find, String replace, {Set<int>? only}) async {
    final src = _originalPdf;
    if (src == null) return;
    setState(() {
      _busy = true;
      _status = 'Editing text…';
    });
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final matches = sf.PdfTextExtractor(doc).findText([find]);
      var applied = 0;
      for (var i = 0; i < matches.length; i++) {
        if (only != null && !only.contains(i)) continue;
        final m = matches[i];
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
        applied++;
      }
      final out = Uint8List.fromList(await doc.save());
      doc.dispose();
      await _applyEditedPdf(out);
      if (mounted) {
        showInfo(context,
            applied == 0 ? 'No matches found' : 'Replaced $applied occurrence(s)');
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

  // ---- Document-wide tools -------------------------------------------------

  /// Runs a Syncfusion edit over the whole document, then re-renders previews.
  Future<void> _runDocEdit(
      String status, void Function(sf.PdfDocument doc) edit) async {
    final src = _originalPdf;
    if (src == null) return;
    setState(() {
      _busy = true;
      _status = status;
    });
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      edit(doc);
      final out = Uint8List.fromList(await doc.save());
      doc.dispose();
      await _applyEditedPdf(out);
      if (mounted) showInfo(context, 'Done');
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

  Future<void> _addWatermark() async {
    final text = await promptText(context,
        title: 'Watermark', hint: 'e.g. CONFIDENTIAL', action: 'Add');
    if (text == null || text.trim().isEmpty) return;
    await _runDocEdit('Adding watermark…', (doc) {
      final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 48,
          style: sf.PdfFontStyle.bold);
      for (var i = 0; i < doc.pages.count; i++) {
        final page = doc.pages[i];
        final g = page.graphics;
        final size = page.size;
        g.save();
        g.setTransparency(0.18);
        g.translateTransform(size.width / 2, size.height / 2);
        g.rotateTransform(-45);
        final ts = font.measureString(text);
        g.drawString(text, font,
            brush: sf.PdfSolidBrush(sf.PdfColor(120, 120, 120)),
            bounds: Rect.fromLTWH(-ts.width / 2, -ts.height / 2, ts.width, ts.height));
        g.restore();
      }
    });
  }

  Future<void> _addPageNumbers() async {
    await _runDocEdit('Numbering pages…', (doc) {
      final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 10);
      final n = doc.pages.count;
      for (var i = 0; i < n; i++) {
        final page = doc.pages[i];
        final size = page.size;
        page.graphics.drawString('${i + 1} / $n', font,
            brush: sf.PdfSolidBrush(sf.PdfColor(80, 80, 80)),
            bounds: Rect.fromLTWH(0, size.height - 28, size.width, 18),
            format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center));
      }
    });
  }

  Future<void> _setPassword() async {
    final pw = await promptText(context,
        title: 'Protect with password', hint: 'Password', action: 'Protect');
    if (pw == null || pw.isEmpty) return;
    await _runDocEdit('Encrypting…', (doc) {
      final sec = doc.security;
      sec.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;
      sec.userPassword = pw;
    });
  }

  Future<void> _editDocInfo() async {
    final src = _originalPdf;
    if (src == null) return;
    var title = '', author = '', subject = '';
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      title = doc.documentInformation.title;
      author = doc.documentInformation.author;
      subject = doc.documentInformation.subject;
      doc.dispose();
    } catch (_) {}
    if (!mounted) return;
    final tc = TextEditingController(text: title);
    final ac = TextEditingController(text: author);
    final sc = TextEditingController(text: subject);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Document info'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: tc,
              decoration: const InputDecoration(labelText: 'Title')),
          TextField(
              controller: ac,
              decoration: const InputDecoration(labelText: 'Author')),
          TextField(
              controller: sc,
              decoration: const InputDecoration(labelText: 'Subject')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    final t = tc.text, a = ac.text, s = sc.text;
    tc.dispose();
    ac.dispose();
    sc.dispose();
    if (ok != true) return;
    await _runDocEdit('Saving info…', (doc) {
      doc.documentInformation.title = t;
      doc.documentInformation.author = a;
      doc.documentInformation.subject = s;
    });
  }

  /// Opens the Acrobat-grade WebViewer editor; applies its edited bytes back.
  Future<void> _openAdvanced() async {
    final src = _originalPdf;
    if (src == null) return;
    final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => ApryseEditorScreen(pdfBytes: src)));
    if (bytes != null && mounted) await _applyEditedPdf(bytes);
  }

  /// Inserts a copy of [page] right after it in the working list.
  void _duplicatePage(_Page page) {
    final i = _pages.indexOf(page);
    if (i < 0) return;
    // The duplicate is a standalone image page (no source-text mapping).
    final copy = _Page(_seq++, page.png, page.aspect)..quarter = page.quarter;
    setState(() => _pages.insert(i + 1, copy));
    showInfo(context, 'Page duplicated');
  }

  /// Inserts a blank white page after [page].
  void _insertBlankAfter(_Page page) {
    final i = _pages.indexOf(page);
    if (i < 0) return;
    final blank = img.Image(width: 850, height: 1100);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    final png = img.encodePng(blank);
    setState(() => _pages.insert(i + 1, _Page(_seq++, png, 850 / 1100)));
    showInfo(context, 'Blank page added');
  }

  /// Exports a single page as its own PDF.
  Future<void> _exportPage(_Page page) async {
    setState(() => _busy = true);
    try {
      final doc = pw.Document();
      final rotated = (page.quarter % 4) == 1 || (page.quarter % 4) == 3;
      final aspect = rotated ? 1 / page.aspect : page.aspect;
      const pageW = 595.0;
      final pageH = pageW / (aspect <= 0 ? 0.7071 : aspect);
      final image = pw.MemoryImage(_rotated(page));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, pageH),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
      await Printing.sharePdf(
          bytes: await doc.save(),
          filename: 'page-${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extractText() async {
    final src = _originalPdf;
    if (src == null) return;
    setState(() {
      _busy = true;
      _status = 'Extracting…';
    });
    var text = '';
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      text = sf.PdfTextExtractor(doc).extractText();
      doc.dispose();
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
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Document text'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
                text.trim().isEmpty ? '(No extractable text)' : text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              showInfo(context, 'Copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _fillForm() async {
    final src = _originalPdf;
    if (src == null) return;
    final fields = <_FormField>[];
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final form = doc.form;
      for (var i = 0; i < form.fields.count; i++) {
        final f = form.fields[i];
        if (f is sf.PdfTextBoxField) {
          fields.add(_FormField(i, f.name ?? 'Field ${i + 1}', false, f.text, false));
        } else if (f is sf.PdfCheckBoxField) {
          fields.add(_FormField(i, f.name ?? 'Field ${i + 1}', true, '', f.isChecked));
        }
      }
      doc.dispose();
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    if (fields.isEmpty) {
      showInfo(context, 'This PDF has no fillable fields');
      return;
    }
    final result = await Navigator.of(context).push<List<_FormField>>(
        MaterialPageRoute(builder: (_) => _FormFillScreen(fields: fields)));
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Saving form…';
    });
    try {
      final doc = sf.PdfDocument(inputBytes: src);
      final form = doc.form;
      for (final ff in result) {
        final field = form.fields[ff.index];
        if (field is sf.PdfTextBoxField) {
          field.text = ff.value;
        } else if (field is sf.PdfCheckBoxField) {
          field.isChecked = ff.checked;
        }
      }
      final out = Uint8List.fromList(await doc.save());
      doc.dispose();
      await _applyEditedPdf(out);
      if (mounted) showInfo(context, 'Form updated');
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

  /// Builds an image-only PDF from the current page previews (no text layer).
  /// Used to truly flatten redacted content.
  Future<Uint8List> _imagesToPdf() async {
    final doc = pw.Document();
    for (final p in _pages) {
      final rotated = (p.quarter % 4) == 1 || (p.quarter % 4) == 3;
      final aspect = rotated ? 1 / p.aspect : p.aspect;
      const pageW = 595.0;
      final pageH = pageW / (aspect <= 0 ? 0.7071 : aspect);
      final image = pw.MemoryImage(_rotated(p));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(pageW, pageH),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ));
    }
    return Uint8List.fromList(await doc.save());
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
            for (final im in p.imgs)
              pw.Positioned(
                left: im.rel.dx * pageW,
                top: im.rel.dy * pageH,
                child: pw.Image(pw.MemoryImage(im.png), width: im.width * pageW),
              ),
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
          if (_pages.isNotEmpty)
            IconButton(
              tooltip: 'Merge another PDF',
              icon: const Icon(Icons.library_add_outlined),
              onPressed: _busy ? null : _mergePdf,
            ),
          IconButton(
            tooltip: 'Add image page',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _busy ? null : _addImage,
          ),
          if (_pages.isNotEmpty && apryseSupported)
            IconButton(
              tooltip: 'Advanced editor (edit text in place)',
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _busy ? null : _openAdvanced,
            ),
          if (_pages.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Document tools',
              icon: const Icon(Icons.tune),
              enabled: !_busy,
              onSelected: (v) {
                switch (v) {
                  case 'watermark':
                    _addWatermark();
                  case 'numbers':
                    _addPageNumbers();
                  case 'password':
                    _setPassword();
                  case 'info':
                    _editDocInfo();
                  case 'extract':
                    _extractText();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'watermark', child: Text('Add watermark')),
                PopupMenuItem(value: 'numbers', child: Text('Add page numbers')),
                PopupMenuItem(
                    value: 'password', child: Text('Protect with password')),
                PopupMenuItem(value: 'info', child: Text('Document info')),
                PopupMenuItem(value: 'extract', child: Text('Extract all text')),
              ],
            ),
          if (_pages.isNotEmpty)
            TextButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.ios_share, size: 20),
              label: const Text('Export'),
            ),
        ],
      ),
      floatingActionButton: liftedFab(
        FloatingActionButton.extended(
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
        // Click a page to open it and edit.
        onTap: _busy ? null : () => _openPage(p, i + 1),
        leading: SizedBox(
          width: 44,
          height: 56,
          child: RotatedBox(
            quarterTurns: p.quarter % 4,
            child: Image.memory(p.png, fit: BoxFit.contain),
          ),
        ),
        title: Text('Page ${i + 1}'),
        subtitle: const Text('Tap to edit'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  Future<void> _addSignature() async {
    final png = await Navigator.of(context)
        .push<Uint8List>(MaterialPageRoute(builder: (_) => const _SignaturePad()));
    if (png != null && mounted) {
      setState(() => _p.imgs.add(_ImgAnno(const Offset(0.3, 0.5), 0.4, png)));
    }
  }

  Future<void> _editImg(_ImgAnno im) async {
    var width = im.width;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Signature'),
          content: Row(children: [
            const Text('Size'),
            Expanded(
              child: Slider(
                value: width,
                min: 0.1,
                max: 0.9,
                onChanged: (v) => setLocal(() => width = v),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, '__delete__'),
                child: const Text('Delete')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'ok'),
                child: const Text('Done')),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (result == '__delete__') {
        _p.imgs.remove(im);
      } else {
        im.width = width;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Markup'),
        actions: [
          IconButton(
            tooltip: 'Add signature',
            icon: const Icon(Icons.draw_outlined),
            onPressed: _addSignature,
          ),
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
                    for (final im in _p.imgs)
                      Positioned(
                        left: im.rel.dx * w,
                        top: im.rel.dy * h,
                        child: GestureDetector(
                          onTap: () => _editImg(im),
                          onPanUpdate: (d) => setState(() {
                            im.rel = Offset(
                              (im.rel.dx + d.delta.dx / w).clamp(0.0, 0.98),
                              (im.rel.dy + d.delta.dy / h).clamp(0.0, 0.98),
                            );
                          }),
                          child: Image.memory(im.png, width: im.width * w),
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

/// A found text match: page index, relative bounds (fraction of page), aspect.
class _Match {
  _Match(this.pageIndex, this.rel, this.aspect);
  final int pageIndex;
  final Rect rel;
  final double aspect;
}

/// Lets the user choose which matches to replace, with each highlighted on a
/// thumbnail of its page. Returns the set of selected match indices.
class _ReviewScreen extends StatefulWidget {
  const _ReviewScreen({required this.matches, required this.pageImage});
  final List<_Match> matches;
  final Uint8List Function(int pageIndex) pageImage;

  @override
  State<_ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<_ReviewScreen> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.matches.length; i++) i
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: Text('${_selected.length} of ${widget.matches.length}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text('Replace')),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: widget.matches.length,
        itemBuilder: (_, i) {
          final m = widget.matches[i];
          final on = _selected.contains(i);
          return Card(
            color: scheme.surfaceContainerHighest,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                CheckboxListTile(
                  value: on,
                  title: Text('Page ${m.pageIndex + 1}'),
                  onChanged: (v) => setState(
                      () => v == true ? _selected.add(i) : _selected.remove(i)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    height: 180,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: m.aspect <= 0 ? 0.7071 : m.aspect,
                        child: LayoutBuilder(
                          builder: (context, c) => Stack(children: [
                            Positioned.fill(
                              child: Container(
                                color: Colors.white,
                                child: Image.memory(widget.pageImage(m.pageIndex),
                                    fit: BoxFit.fill),
                              ),
                            ),
                            Positioned(
                              left: m.rel.left * c.maxWidth,
                              top: m.rel.top * c.maxHeight,
                              width: m.rel.width * c.maxWidth,
                              height: m.rel.height * c.maxHeight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.yellow.withValues(alpha: 0.4),
                                  border: Border.all(
                                      color: Colors.orange, width: 1.5),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One editable form field captured from the PDF's AcroForm.
class _FormField {
  _FormField(this.index, this.name, this.isCheck, this.value, this.checked);
  final int index;
  final String name;
  final bool isCheck;
  String value;
  bool checked;
}

/// Edits the PDF's fillable form fields; returns the updated list on save.
class _FormFillScreen extends StatefulWidget {
  const _FormFillScreen({required this.fields});
  final List<_FormField> fields;

  @override
  State<_FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<_FormFillScreen> {
  late final List<TextEditingController> _controllers = [
    for (final f in widget.fields) TextEditingController(text: f.value)
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Fill form'),
        actions: [
          TextButton(
            onPressed: () {
              for (var i = 0; i < widget.fields.length; i++) {
                widget.fields[i].value = _controllers[i].text;
              }
              Navigator.pop(context, widget.fields);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: widget.fields.length,
        itemBuilder: (_, i) {
          final f = widget.fields[i];
          if (f.isCheck) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(f.name),
              value: f.checked,
              onChanged: (v) => setState(() => f.checked = v),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(
              controller: _controllers[i],
              decoration: InputDecoration(
                  labelText: f.name, border: const OutlineInputBorder()),
            ),
          );
        },
      ),
    );
  }
}

/// A freehand signature pad. Returns the drawing as a transparent PNG.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad();

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];
  Size _size = const Size(300, 200);

  Future<void> _done() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in _strokes) {
      if (s.length == 1) {
        canvas.drawPoints(ui.PointMode.points, s, paint);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final image = await recorder
        .endRecording()
        .toImage(_size.width.ceil().clamp(1, 4000), _size.height.ceil().clamp(1, 4000));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(context, data?.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Signature'),
        actions: [
          TextButton(
              onPressed: () => setState(() => _strokes.clear()),
              child: const Text('Clear')),
          TextButton(onPressed: _done, child: const Text('Done')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  _size = Size(c.maxWidth, c.maxHeight);
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: GestureDetector(
                      onPanStart: (d) =>
                          setState(() => _strokes.add([d.localPosition])),
                      onPanUpdate: (d) =>
                          setState(() => _strokes.last.add(d.localPosition)),
                      child: CustomPaint(
                        painter: _SigPainter(_strokes),
                        size: Size.infinite,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text('Sign above', style: TextStyle(color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawPoints(ui.PointMode.points, s, paint);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SigPainter old) => true;
}

/// Tap or drag across the page to select words, then replace them. Returns the
/// edit (which words to clear, the replacement text, and where to draw it).
class _TextSelectScreen extends StatefulWidget {
  const _TextSelectScreen(
      {required this.pageImage,
      required this.aspect,
      required this.pageIndex,
      required this.words});
  final Uint8List pageImage;
  final double aspect;
  final int pageIndex;
  final List<_Word> words;

  @override
  State<_TextSelectScreen> createState() => _TextSelectScreenState();
}

class _TextSelectScreenState extends State<_TextSelectScreen> {
  final Set<int> _sel = {};
  Offset? _dragStart;
  Rect? _dragRect; // relative selection rectangle while dragging

  void _selectIn(Rect rel) {
    _sel.clear();
    for (var i = 0; i < widget.words.length; i++) {
      if (widget.words[i].rel.overlaps(rel)) _sel.add(i);
    }
  }

  String get _selectedText {
    final idx = _sel.toList()..sort();
    return idx.map((i) => widget.words[i].text).join(' ');
  }

  ({List<Rect> clears, Rect union, _Word first}) _selBounds() {
    final idx = _sel.toList()..sort();
    final first = widget.words[idx.first];
    final clears = [for (final i in idx) widget.words[i].pdf];
    var union = clears.first;
    for (final r in clears) {
      union = union.expandToInclude(r);
    }
    return (clears: clears, union: union, first: first);
  }

  Future<void> _replace() async {
    if (_sel.isEmpty) return;
    final controller = TextEditingController(text: _selectedText);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace selected text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Replacement text'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Replace')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final b = _selBounds();
    // Use the same size/style as the text being replaced.
    Navigator.pop(
        context,
        _TextEdit(widget.pageIndex, b.clears, b.union, result, b.first.fontSize,
            b.first.bold, b.first.italic));
  }

  void _markup(String mode) {
    if (_sel.isEmpty) return;
    final b = _selBounds();
    Navigator.pop(
        context,
        _TextEdit(widget.pageIndex, b.clears, b.union, '', b.first.fontSize,
            b.first.bold, b.first.italic,
            mode: mode));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(_sel.isEmpty ? 'Select text' : '${_sel.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Highlight',
            onPressed: _sel.isEmpty ? null : () => _markup('highlight'),
            icon: const Icon(Icons.highlight),
          ),
          IconButton(
            tooltip: 'Redact',
            onPressed: _sel.isEmpty ? null : () => _markup('redact'),
            icon: const Icon(Icons.format_color_fill),
          ),
          TextButton(
            onPressed: _sel.isEmpty ? null : _replace,
            child: const Text('Replace'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
                _sel.isEmpty
                    ? 'Drag across words, then replace, highlight, or redact.'
                    : '“$_selectedText”',
                style: TextStyle(color: scheme.outline)),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AspectRatio(
                  aspectRatio: widget.aspect <= 0 ? 0.7071 : widget.aspect,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth, h = c.maxHeight;
                      return GestureDetector(
                        onPanStart: (d) => _dragStart = d.localPosition,
                        onPanUpdate: (d) {
                          final s = _dragStart;
                          if (s == null) return;
                          final rect = Rect.fromPoints(s, d.localPosition);
                          setState(() {
                            _dragRect = Rect.fromLTRB(rect.left / w,
                                rect.top / h, rect.right / w, rect.bottom / h);
                            _selectIn(_dragRect!);
                          });
                        },
                        onPanEnd: (_) => setState(() => _dragRect = null),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                color: Colors.white,
                                child: Image.memory(widget.pageImage,
                                    fit: BoxFit.fill),
                              ),
                            ),
                            for (var i = 0; i < widget.words.length; i++)
                              Positioned(
                                left: widget.words[i].rel.left * w,
                                top: widget.words[i].rel.top * h,
                                width: widget.words[i].rel.width * w,
                                height: widget.words[i].rel.height * h,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _sel.contains(i)
                                        ? _sel.remove(i)
                                        : _sel.add(i);
                                  }),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _sel.contains(i)
                                          ? Colors.blue.withValues(alpha: 0.35)
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single page opened for editing. Returns the chosen action to the editor:
/// 'editText', 'markup', 'form', 'extract', or null (just viewed / rotated).
class _PageScreen extends StatefulWidget {
  const _PageScreen({required this.page, required this.pageNumber});
  final _Page page;
  final int pageNumber;

  @override
  State<_PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<_PageScreen> {
  _Page get p => widget.page;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: Text('Page ${widget.pageNumber}'),
        actions: [
          IconButton(
            tooltip: 'Rotate',
            icon: const Icon(Icons.rotate_right),
            onPressed: () => setState(() => p.quarter += 1),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onSelected: (v) => Navigator.pop(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'editText', child: Text('Edit text (select & replace)')),
              PopupMenuItem(value: 'find', child: Text('Find & replace')),
              PopupMenuItem(value: 'markup', child: Text('Add text / signature')),
              PopupMenuItem(value: 'form', child: Text('Fill form fields')),
              PopupMenuItem(value: 'extract', child: Text('Extract text')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'duplicate', child: Text('Duplicate page')),
              PopupMenuItem(
                  value: 'blankAfter', child: Text('Insert blank page after')),
              PopupMenuItem(value: 'exportPage', child: Text('Export this page')),
            ],
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: RotatedBox(
              quarterTurns: p.quarter % 4,
              child: Image.memory(p.png, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
