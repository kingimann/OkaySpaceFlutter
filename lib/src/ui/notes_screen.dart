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
  late bool _pinned = widget.note?.pinned ?? false;
  bool _done = false; // guard against double-save (Done + pop)

  bool get _empty =>
      _title.text.trim().isEmpty && _body.text.trim().isEmpty;
  bool get _changed =>
      _title.text != (widget.note?.title ?? '') ||
      _body.text != (widget.note?.body ?? '') ||
      _pinned != (widget.note?.pinned ?? false);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Persists on leave (Apple Notes-style auto-save). Returns whether the list
  /// needs refreshing.
  Future<bool> _persist() async {
    final n = widget.note;
    try {
      if (n == null) {
        if (_empty) return false; // nothing typed
        await api.notes
            .create(title: _title.text, body: _body.text, pinned: _pinned);
        return true;
      }
      if (_empty) {
        await api.notes.delete(n.id); // emptied → remove
        return true;
      }
      if (!_changed) return false;
      await api.notes.update(n.id,
          title: _title.text, body: _body.text, color: n.color,
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
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => setState(() => _pinned = !_pinned),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'copy' ? _copy() : _delete(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'copy', child: Text('Copy text')),
                if (widget.note != null)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            TextButton(onPressed: _leave, child: const Text('Done')),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.note == null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    isCollapsed: true),
              ),
              if (when != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(_stamp(when),
                      style: TextStyle(color: scheme.outline, fontSize: 12)),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: TextField(
                  controller: _body,
                  textCapitalization: TextCapitalization.sentences,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 17, height: 1.4),
                  decoration: const InputDecoration(
                      hintText: 'Write something…', border: InputBorder.none),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
