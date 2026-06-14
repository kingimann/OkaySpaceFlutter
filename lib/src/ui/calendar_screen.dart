import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

const _fullMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

DateTime _dayOf(DateTime x) => DateTime(x.year, x.month, x.day);

/// Personal calendar: a month grid plus the selected day's events, with
/// create / edit / delete.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late Future<List<CalendarEvent>> _future;
  DateTime _focused = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selected = _dayOf(DateTime.now());

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

  Future<void> _edit({CalendarEvent? event, DateTime? initialStart}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventEditor(event: event, initialStart: initialStart),
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

  /// Maps each local day to the events occurring on it (covering multi-day
  /// events across their range).
  Map<DateTime, List<CalendarEvent>> _byDayMap(List<CalendarEvent> events) {
    final map = <DateTime, List<CalendarEvent>>{};
    for (final e in events) {
      var day = _dayOf(e.startAt.toLocal());
      final last = _dayOf((e.endAt ?? e.startAt).toLocal());
      var guard = 0;
      while (!day.isAfter(last) && guard < 366) {
        map.putIfAbsent(day, () => []).add(e);
        day = day.add(const Duration(days: 1));
        guard++;
      }
    }
    return map;
  }

  void _shiftMonth(int by) => setState(
      () => _focused = DateTime(_focused.year, _focused.month + by, 1));

  void _goToday() => setState(() {
        final now = DateTime.now();
        _focused = DateTime(now.year, now.month, 1);
        _selected = _dayOf(now);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Calendar')),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: () => _edit(
              initialStart: DateTime(
                  _selected.year, _selected.month, _selected.day, 9)),
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
          final byDay = _byDayMap(snap.data ?? const <CalendarEvent>[]);
          final dayEvents = byDay[_selected] ?? const <CalendarEvent>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                _monthHeader(),
                const SizedBox(height: 8),
                _weekdayHeader(),
                _grid(byDay),
                const Divider(height: 28),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(_dayLabel(_selected),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (dayEvents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Nothing scheduled',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline)),
                    ),
                  )
                else
                  for (final e in dayEvents)
                    _EventTile(event: e, onTap: _edit, onDelete: _delete),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _monthHeader() {
    return Row(
      children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftMonth(-1)),
        Expanded(
          child: Center(
            child: Text('${_fullMonths[_focused.month - 1]} ${_focused.year}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Today',
            onPressed: _goToday),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftMonth(1)),
      ],
    );
  }

  Widget _weekdayHeader() {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final l in labels)
          Expanded(
            child: Center(
              child: Text(l,
                  style: TextStyle(
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Widget _grid(Map<DateTime, List<CalendarEvent>> byDay) {
    final daysIn = DateTime(_focused.year, _focused.month + 1, 0).day;
    final lead = DateTime(_focused.year, _focused.month, 1).weekday % 7; // Sun=0
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= daysIn; d++)
        DateTime(_focused.year, _focused.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Row(
        children: [
          for (var j = 0; j < 7; j++) Expanded(child: _cell(cells[i + j], byDay)),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _cell(DateTime? day, Map<DateTime, List<CalendarEvent>> byDay) {
    if (day == null) return const SizedBox(height: 46);
    final scheme = Theme.of(context).colorScheme;
    final selected = _dayOf(day) == _selected;
    final today = _isToday(day);
    final hasEvents = (byDay[_dayOf(day)] ?? const []).isNotEmpty;
    return GestureDetector(
      onTap: () => setState(() => _selected = _dayOf(day)),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 46,
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : Colors.transparent,
              border: (today && !selected)
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${day.day}',
                    style: TextStyle(
                        fontWeight:
                            today || selected ? FontWeight.bold : null,
                        color: selected
                            ? Colors.white
                            : (today ? scheme.primary : null))),
                const SizedBox(height: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasEvents
                        ? (selected ? Colors.white : scheme.primary)
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(
      {required this.event, required this.onTap, required this.onDelete});

  final CalendarEvent event;
  final void Function({CalendarEvent? event, DateTime? initialStart}) onTap;
  final void Function(CalendarEvent) onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(event: event),
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
                      Text(event.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(_timeLabel(event),
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                      if ((event.notes ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(event.notes!,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (_) => onDelete(event),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
  const _EventEditor({this.event, this.initialStart});
  final CalendarEvent? event;
  final DateTime? initialStart;

  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.event?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.event?.notes ?? '');
  late DateTime _start =
      widget.event?.startAt.toLocal() ?? widget.initialStart ?? _defaultStart();
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
