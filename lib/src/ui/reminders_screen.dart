import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Personal reminders / to-dos: a checklist with optional due dates.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late Future<List<Reminder>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = api.reminders.list();

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  Future<void> _toggle(Reminder r) async {
    try {
      await api.reminders
          .update(r.id, text: r.text, dueAt: r.dueAt, done: !r.done);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Reminder r) async {
    try {
      await api.reminders.delete(r.id);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit([Reminder? r]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReminderEditor(reminder: r),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Reminders')),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('New reminder'),
        ),
      ),
      body: FutureBuilder<List<Reminder>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const ListSkeleton();
          }
          if (snap.hasError) {
            return CenteredMessage(
                message: "Couldn't load your reminders",
                icon: Icons.error_outline,
                onRetry: _reload);
          }
          final items = snap.data ?? const <Reminder>[];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: const CenteredMessage(
                  message: 'Nothing to do.\nTap “New reminder” to add a to-do.',
                  icon: Icons.checklist_rtl_outlined),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _tile(items[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _tile(Reminder r) {
    final scheme = Theme.of(context).colorScheme;
    final overdue =
        !r.done && r.dueAt != null && r.dueAt!.toLocal().isBefore(DateTime.now());
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                    r.done ? Icons.check_circle : Icons.circle_outlined,
                    color: r.done ? scheme.primary : scheme.outline),
                onPressed: () => _toggle(r),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.text,
                        style: TextStyle(
                            fontSize: 15,
                            decoration:
                                r.done ? TextDecoration.lineThrough : null,
                            color: r.done ? scheme.outline : null)),
                    if (r.dueAt != null)
                      Text(_due(r.dueAt!.toLocal()),
                          style: TextStyle(
                              fontSize: 12,
                              color: overdue ? scheme.error : scheme.outline)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Delete',
                onPressed: () => _delete(r),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

String _due(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final time = '$h:${d.minute.toString().padLeft(2, '0')} '
      '${d.hour < 12 ? 'AM' : 'PM'}';
  String label;
  if (diff == 0) {
    label = 'Today';
  } else if (diff == 1) {
    label = 'Tomorrow';
  } else if (diff == -1) {
    label = 'Yesterday';
  } else {
    label = '${_months[d.month - 1]} ${d.day}';
  }
  return '$label · $time';
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({this.reminder});
  final Reminder? reminder;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.reminder?.text ?? '');
  late DateTime? _due = widget.reminder?.dueAt?.toLocal();
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_due ?? now));
    if (!mounted) return;
    setState(() => _due = DateTime(
        d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      showError(context, 'Enter the reminder');
      return;
    }
    setState(() => _saving = true);
    try {
      final r = widget.reminder;
      if (r == null) {
        await api.reminders.create(_text.text.trim(), dueAt: _due);
      } else {
        await api.reminders
            .update(r.id, text: _text.text.trim(), dueAt: _due, done: r.done);
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
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
                hintText: 'Remind me to…', border: InputBorder.none),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm),
            title: Text(_due == null ? 'Add a due date' : _due!.toLocal().toString().split('.').first),
            trailing: _due == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _due = null)),
            onTap: _pickDue,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.reminder == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }
}
