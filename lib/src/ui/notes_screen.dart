import 'package:flutter/material.dart';

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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteEditor(note: note),
    );
    if (saved == true) _reload();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('New note'),
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
            return CenteredMessage(
                message: 'No notes yet.\nTap “New note” to jot one down.',
                icon: Icons.sticky_note_2_outlined,
                onRetry: _reload);
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

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({this.note});
  final Note? note;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      final n = widget.note;
      if (n == null) {
        await api.notes.create(title: _title.text, body: _body.text);
      } else {
        await api.notes.update(n.id,
            title: _title.text, body: _body.text, color: n.color,
            pinned: n.pinned);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
                hintText: 'Title', border: InputBorder.none),
          ),
          TextField(
            controller: _body,
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 12,
            decoration: const InputDecoration(
                hintText: 'Write something…', border: InputBorder.none),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.note == null ? 'Save note' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}
