import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Events for a group: list, RSVP, and create.
class GroupEventsScreen extends StatefulWidget {
  const GroupEventsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupEventsScreen> createState() => _GroupEventsScreenState();
}

class _GroupEventsScreenState extends State<GroupEventsScreen> {
  late Future<List<GroupEvent>> _events;

  @override
  void initState() {
    super.initState();
    _events = api.groups.events(widget.groupId);
  }

  Future<void> _reload() async {
    setState(() => _events = api.groups.events(widget.groupId));
    await _events;
  }

  Future<void> _rsvp(GroupEvent e) async {
    try {
      await api.groups.rsvpEvent(widget.groupId, e.id);
      await _reload();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _NewEventSheet(groupId: widget.groupId),
      ),
    );
    if (created == true) _reload();
  }

  String _when(DateTime d) {
    final local = d.toLocal();
    final date = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Events')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.event),
        label: const Text('New event'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<GroupEvent>(
          future: _events,
          loading: const ListSkeleton(),
          emptyMessage: 'No upcoming events.',
          emptyIcon: Icons.event_outlined,
          builder: (context, items) => ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = items[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text('${e.startsAt.toLocal().day}'),
                ),
                title: Text(e.title),
                subtitle: Text([
                  _when(e.startsAt),
                  if (e.location != null && e.location!.isNotEmpty) e.location!,
                  '${e.goingCount} going',
                ].join('\n')),
                isThreeLine: true,
                trailing: FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _rsvp(e),
                  child: Text(e.going ? 'Going' : 'RSVP'),
                ),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

class _NewEventSheet extends StatefulWidget {
  const _NewEventSheet({required this.groupId});

  final String groupId;

  @override
  State<_NewEventSheet> createState() => _NewEventSheetState();
}

class _NewEventSheetState extends State<_NewEventSheet> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  DateTime _starts = DateTime.now().add(const Duration(days: 1));
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _starts,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_starts),
    );
    if (!mounted) return;
    setState(() => _starts = DateTime(date.year, date.month, date.day,
        time?.hour ?? _starts.hour, time?.minute ?? _starts.minute));
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await api.groups.createEvent(
        widget.groupId,
        title: _title.text.trim(),
        startsAt: _starts,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New event',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
                labelText: 'Location (optional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDateTime,
            icon: const Icon(Icons.schedule),
            label: Text(
                'Starts: ${_starts.toLocal()}'.split('.').first),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create event'),
            ),
          ),
        ],
      ),
    );
  }
}
