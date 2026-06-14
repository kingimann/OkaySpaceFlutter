import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Personal calendar: an agenda of upcoming events with create / edit / delete.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late Future<List<CalendarEvent>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = api.calendar.events();

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  Future<void> _edit([CalendarEvent? event]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventEditor(event: event),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(CalendarEvent e) async {
    try {
      await api.calendar.delete(e.id);
      _reload();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  /// Groups events by local calendar day, preserving the soonest-first order.
  List<MapEntry<DateTime, List<CalendarEvent>>> _byDay(
      List<CalendarEvent> events) {
    final map = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      final d = e.startAt.toLocal();
      final key = DateTime(d.year, d.month, d.day);
      map.putIfAbsent(key, () => []).add(e);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Calendar')),
      // Lifted so it clears the floating bottom nav on pushed screens.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('New event'),
        ),
      ),
      body: FutureBuilder<List<CalendarEvent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const ListSkeleton();
          }
          if (snap.hasError) {
            return CenteredMessage(
                message: "Couldn't load your calendar",
                icon: Icons.error_outline,
                onRetry: _reload);
          }
          final events = snap.data ?? const <CalendarEvent>[];
          if (events.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reload,
              child: const CenteredMessage(
                  message: 'No events yet.\nTap “New event” to add one.',
                  icon: Icons.event_outlined),
            );
          }
          final groups = _byDay(events);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: groups.length,
              itemBuilder: (context, i) => _DaySection(
                day: groups[i].key,
                events: groups[i].value,
                onTap: _edit,
                onDelete: _delete,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection(
      {required this.day,
      required this.events,
      required this.onTap,
      required this.onDelete});

  final DateTime day;
  final List<CalendarEvent> events;
  final void Function(CalendarEvent) onTap;
  final void Function(CalendarEvent) onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
          child: Text(_dayLabel(day),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _isToday(day) ? scheme.primary : null)),
        ),
        for (final e in events)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(e),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        height: 38,
                        margin: const EdgeInsets.only(right: 12, top: 2),
                        decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(_timeLabel(e),
                                style:
                                    TextStyle(color: scheme.onSurfaceVariant)),
                            if ((e.notes ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(e.notes!,
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (_) => onDelete(e),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

bool _isToday(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayLabel(DateTime d) {
  if (_isToday(d)) return 'Today';
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  if (d.year == tomorrow.year &&
      d.month == tomorrow.month &&
      d.day == tomorrow.day) {
    return 'Tomorrow';
  }
  return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

String _hhmm(DateTime d) {
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

String _timeLabel(CalendarEvent e) {
  if (e.allDay) return 'All day';
  final start = _hhmm(e.startAt);
  if (e.endAt == null) return start;
  return '$start – ${_hhmm(e.endAt!)}';
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({this.event});
  final CalendarEvent? event;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.event?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.event?.notes ?? '');
  late DateTime _start =
      widget.event?.startAt.toLocal() ?? _defaultStart();
  late DateTime? _end = widget.event?.endAt?.toLocal();
  late bool _allDay = widget.event?.allDay ?? false;
  bool _saving = false;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (d == null || !mounted) return;
    var picked = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
    if (!_allDay) {
      final t = await showTimePicker(
          context: context, initialTime: TimeOfDay.fromDateTime(_start));
      if (t != null) {
        picked = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      }
    }
    setState(() {
      _start = picked;
      if (_end != null && _end!.isBefore(_start)) _end = null;
    });
  }

  Future<void> _pickEnd() async {
    final base = _end ?? _start.add(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _start,
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (d == null || !mounted) return;
    var picked = DateTime(d.year, d.month, d.day, base.hour, base.minute);
    if (!_allDay) {
      final t = await showTimePicker(
          context: context, initialTime: TimeOfDay.fromDateTime(base));
      if (t != null) {
        picked = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      }
    }
    setState(() => _end = picked.isBefore(_start) ? _start : picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showError(context, 'Give the event a title');
      return;
    }
    setState(() => _saving = true);
    try {
      final e = widget.event;
      if (e == null) {
        await api.calendar.create(
            title: _title.text.trim(),
            startAt: _start,
            endAt: _end,
            allDay: _allDay,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
      } else {
        await api.calendar.update(e.id,
            title: _title.text.trim(),
            startAt: _start,
            endAt: _end,
            allDay: _allDay,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, err);
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
                hintText: 'Event title', border: InputBorder.none),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Starts'),
            subtitle: Text(_allDay
                ? _dateOnly(_start)
                : '${_dateOnly(_start)} · ${_hhmm(_start)}'),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Ends'),
            subtitle: Text(_end == null
                ? 'Optional'
                : (_allDay
                    ? _dateOnly(_end!)
                    : '${_dateOnly(_end!)} · ${_hhmm(_end!)}')),
            trailing: _end == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _end = null)),
            onTap: _pickEnd,
          ),
          TextField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(
                hintText: 'Notes (optional)', border: InputBorder.none),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.event == null ? 'Add event' : 'Save changes'),
          ),
        ],
      ),
    );
  }

  String _dateOnly(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}
