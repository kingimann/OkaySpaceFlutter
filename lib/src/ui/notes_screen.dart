import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Personal notes: a list with create / edit / pin / delete.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late Future<List<Note>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = api.notes.list();

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  Future<void> _edit([Note? note]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
    );
    if (changed == true) _reload();
  }

  Future<void> _togglePin(Note n) async {
    try {
      await api.notes.update(n.id,
          title: n.title, body: n.body, color: n.color, pinned: !n.pinned);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Note n) async {
    try {
      await api.notes.delete(n.id);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Notes')),
      // Lifted so it clears the floating bottom nav on pushed screens.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('New note'),
        ),
      ),
      body: FutureBuilder<List<Note>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const ListSkeleton();
          }
          if (snap.hasError) {
            return CenteredMessage(
                message: "Couldn't load your notes",
                icon: Icons.error_outline,
                onRetry: _reload);
          }
          final notes = snap.data ?? const <Note>[];
          if (notes.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: const CenteredMessage(
                  message: 'No notes yet.\nTap “New note” to jot one down.',
                  icon: Icons.sticky_note_2_outlined),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _NoteTile(
                note: notes[i],
                onTap: () => _edit(notes[i]),
                onPin: () => _togglePin(notes[i]),
                onDelete: () => _delete(notes[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile(
      {required this.note,
      required this.onTap,
      required this.onPin,
      required this.onDelete});

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTitle = note.title.trim().isNotEmpty;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasTitle ? note.title : 'Untitled',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: hasTitle ? null : scheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (note.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(note.body,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (note.pinned)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.push_pin, size: 18, color: scheme.primary),
                ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'pin' ? onPin() : onDelete(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'pin',
                      child: Text(note.pinned ? 'Unpin' : 'Pin')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-screen, Apple Notes-style editor: a big title line, an edited-at
/// timestamp, and a body that fills the screen. Auto-saves on leave; emptying
/// an existing note deletes it. Pin/Copy/Delete live in the toolbar.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.note});
  final Note? note;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  final UndoHistoryController _undo = UndoHistoryController();
  late bool _pinned = widget.note?.pinned ?? false;
  late String? _color = widget.note?.color;
  bool _done = false; // guard against double-save (Done + pop)

  static const _palette = <String, Color>{
    'red': Color(0xFFEF4444),
    'orange': Color(0xFFF59E0B),
    'green': Color(0xFF22C55E),
    'blue': Color(0xFF3B82F6),
    'purple': Color(0xFF8B5CF6),
  };
  Color? get _accent => _color == null ? null : _palette[_color];

  bool get _empty =>
      _title.text.trim().isEmpty && _body.text.trim().isEmpty;
  bool get _changed =>
      _title.text != (widget.note?.title ?? '') ||
      _body.text != (widget.note?.body ?? '') ||
      _color != widget.note?.color ||
      _pinned != (widget.note?.pinned ?? false);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _undo.dispose();
    super.dispose();
  }

  /// Persists on leave (Apple Notes-style auto-save). Returns whether the list
  /// needs refreshing.
  Future<bool> _persist() async {
    final n = widget.note;
    try {
      if (n == null) {
        if (_empty) return false; // nothing typed
        await api.notes.create(
            title: _title.text, body: _body.text, color: _color,
            pinned: _pinned);
        return true;
      }
      if (_empty) {
        await api.notes.delete(n.id); // emptied → remove
        return true;
      }
      if (!_changed) return false;
      await api.notes.update(n.id,
          title: _title.text, body: _body.text, color: _color,
          pinned: _pinned);
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    }
  }

  Future<void> _leave() async {
    if (_done) return;
    _done = true;
    final changed = await _persist();
    if (mounted) Navigator.pop(context, changed);
  }

  Future<void> _delete() async {
    _done = true;
    final n = widget.note;
    if (n != null) {
      try {
        await api.notes.delete(n.id);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context, true);
  }

  void _copy() {
    final text = [_title.text, _body.text]
        .where((s) => s.trim().isNotEmpty)
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    showInfo(context, 'Copied');
  }

  int get _wordCount {
    final t = _body.text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  // --- list / line formatting -------------------------------------------
  static final _markers = RegExp(r'^(?:[☐☑]\s|•\s|\d+\.\s)');
  String _strip(String line) => line.replaceFirst(_markers, '');

  void _applyToLine(String Function(String) f) {
    final text = _body.text;
    final caret =
        _body.selection.baseOffset < 0 ? text.length : _body.selection.baseOffset;
    final start = text.lastIndexOf('\n', caret > 0 ? caret - 1 : 0) + 1;
    var end = text.indexOf('\n', caret);
    if (end < 0) end = text.length;
    final nl = f(text.substring(start, end));
    final newText = text.replaceRange(start, end, nl);
    _body.value = TextEditingValue(
        text: newText, selection: TextSelection.collapsed(offset: start + nl.length));
  }

  void _checklist() => _applyToLine((l) {
        if (l.startsWith('☐ ')) return '☑ ${l.substring(2)}'; // ☐ → ☑
        if (l.startsWith('☑ ')) return l.substring(2); // ☑ → none
        return '☐ ${_strip(l)}';
      });
  void _bullet() => _applyToLine(
      (l) => l.startsWith('• ') ? l.substring(2) : '• ${_strip(l)}');
  void _numbered() => _applyToLine((l) =>
      RegExp(r'^\d+\.\s').hasMatch(l) ? _strip(l) : '1. ${_strip(l)}');

  void _insertDate() {
    final t = _body.text;
    final caret =
        _body.selection.baseOffset < 0 ? t.length : _body.selection.baseOffset;
    final ins = _stamp(DateTime.now()).replaceFirst('Edited ', '');
    _body.value = TextEditingValue(
        text: t.replaceRange(caret, caret, ins),
        selection: TextSelection.collapsed(offset: caret + ins.length));
  }

  void _pickColor() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Note colour',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Wrap(spacing: 16, runSpacing: 16, children: [
                _swatch(ctx, null),
                for (final k in _palette.keys) _swatch(ctx, k),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(BuildContext ctx, String? key) {
    final scheme = Theme.of(ctx).colorScheme;
    final c = key == null ? null : _palette[key];
    final selected = _color == key;
    return GestureDetector(
      onTap: () {
        setState(() => _color = key);
        Navigator.pop(ctx);
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c ?? scheme.surfaceContainerHighest,
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1.5),
        ),
        child: key == null
            ? Icon(Icons.block, size: 20, color: scheme.outline)
            : (selected
                ? const Icon(Icons.check, color: Colors.white)
                : null),
      ),
    );
  }

  Widget _toolbar() {
    final scheme = Theme.of(context).colorScheme;
    Widget btn(IconData i, String t, VoidCallback on) => IconButton(
        icon: Icon(i), tooltip: t, onPressed: on,
        visualDensity: VisualDensity.compact);
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: _undo,
              builder: (_, v, __) => Row(children: [
                IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: v.canUndo ? _undo.undo : null),
                IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: v.canRedo ? _undo.redo : null),
              ]),
            ),
            const SizedBox(width: 2),
            btn(Icons.checklist, 'Checklist', _checklist),
            btn(Icons.format_list_bulleted, 'Bullet list', _bullet),
            btn(Icons.format_list_numbered, 'Numbered list', _numbered),
            btn(Icons.palette_outlined, 'Note colour', _pickColor),
            btn(Icons.event_outlined, 'Insert date', _insertDate),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = widget.note?.updatedAt.toLocal();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: OkayAppBar(
          title: const Text('Note'),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin',
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _pinned ? scheme.primary : null),
              onPressed: () => setState(() => _pinned = !_pinned),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'copy' ? _copy() : _delete(),
              itemBuilder: (_) => [
                PopupMenuItem(
                    enabled: false,
                    child: Text('$_wordCount words',
                        style: TextStyle(color: scheme.outline))),
                const PopupMenuItem(value: 'copy', child: Text('Copy text')),
                if (widget.note != null)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            TextButton(onPressed: _leave, child: const Text('Done')),
          ],
        ),
        body: Column(
          children: [
            if (_accent != null) Container(height: 3, color: _accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _title,
                      autofocus: widget.note == null,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      cursorColor: _accent,
                      style: const TextStyle(
                          fontSize: 25, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                          hintText: 'Title',
                          border: InputBorder.none,
                          isCollapsed: true),
                    ),
                    if (when != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: Text(_stamp(when),
                            style:
                                TextStyle(color: scheme.outline, fontSize: 12)),
                      ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: TextField(
                        controller: _body,
                        undoController: _undo,
                        inputFormatters: [_ListContinuationFormatter()],
                        textCapitalization: TextCapitalization.sentences,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        cursorColor: _accent,
                        style: const TextStyle(fontSize: 17, height: 1.5),
                        decoration: const InputDecoration(
                            hintText: 'Start writing…',
                            border: InputBorder.none),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _toolbar(),
          ],
        ),
      ),
    );
  }
}

/// Continues a list when you press Enter: bullets, numbered items and
/// checklist boxes carry to the next line (an empty item ends the list) —
/// mirroring Apple Notes.
class _ListContinuationFormatter extends TextInputFormatter {
  static final _line = RegExp(r'^(\s*)([☐☑] |• |\d+\. )(.*)$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    final caret = newValue.selection.baseOffset;
    if (caret <= 0 || caret > newValue.text.length ||
        newValue.text[caret - 1] != '\n') {
      return newValue;
    }
    final before = newValue.text.substring(0, caret - 1);
    final lineStart = before.lastIndexOf('\n') + 1;
    final prevLine = before.substring(lineStart);
    final m = _line.firstMatch(prevLine);
    if (m == null) return newValue;
    final indent = m.group(1)!;
    final marker = m.group(2)!;
    final content = m.group(3)!;
    if (content.trim().isEmpty) {
      // Empty item → end the list (drop the marker line).
      final text =
          newValue.text.substring(0, lineStart) + newValue.text.substring(caret);
      return TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: lineStart));
    }
    var next = marker;
    final num = RegExp(r'^(\d+)\. ').firstMatch(marker);
    if (num != null) {
      next = '${int.parse(num.group(1)!) + 1}. ';
    } else if (marker == '☑ ') {
      next = '☐ '; // continue checklists unchecked
    }
    final insert = indent + next;
    final text = newValue.text.substring(0, caret) +
        insert +
        newValue.text.substring(caret);
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: caret + insert.length));
  }
}

String _stamp(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return 'Edited ${months[d.month - 1]} ${d.day}, ${d.year} '
      'at $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
