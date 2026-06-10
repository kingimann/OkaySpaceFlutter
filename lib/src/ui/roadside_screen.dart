import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

const _services = <(String, String, IconData)>[
  ('fuel', 'Out of fuel', Icons.local_gas_station),
  ('battery', 'Battery / jump start', Icons.battery_charging_full),
  ('tire', 'Flat tire', Icons.tire_repair),
  ('lockout', 'Locked out', Icons.lock_outline),
  ('tow', 'Tow', Icons.local_shipping),
  ('other', 'Something else', Icons.build_outlined),
];

String _serviceLabel(String key) =>
    _services.firstWhere((s) => s.$1 == key, orElse: () => (key, key, Icons.help_outline)).$2;

/// Roadside assistance: your requests plus a button to request help.
class RoadsideScreen extends StatefulWidget {
  const RoadsideScreen({super.key});

  @override
  State<RoadsideScreen> createState() => _RoadsideScreenState();
}

class _RoadsideScreenState extends State<RoadsideScreen> {
  late Future<List<RoadsideRequest>> _mine;

  @override
  void initState() {
    super.initState();
    _mine = api.roadside.mine();
  }

  Future<void> _reload() async {
    setState(() => _mine = api.roadside.mine());
    await _mine;
  }

  Future<void> _request() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const RoadsideRequestForm(),
    ));
    if (created == true) _reload();
  }

  Future<void> _cancel(RoadsideRequest r) async {
    try {
      await api.roadside.cancel(r.id);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roadside assistance')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _request,
        icon: const Icon(Icons.add_alert),
        label: const Text('Request help'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<RoadsideRequest>(
          future: _mine,
          loading: const ListSkeleton(),
          emptyMessage: 'No roadside requests.\nTap “Request help” if you’re stuck.',
          emptyIcon: Icons.car_repair,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = items[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(_services
                      .firstWhere((s) => s.$1 == r.service,
                          orElse: () => ('', '', Icons.help_outline))
                      .$3),
                ),
                title: Text(_serviceLabel(r.service)),
                subtitle: Text(
                    '${r.status}${r.placeName != null ? ' · ${r.placeName}' : ''} · ${shortAgo(r.createdAt)}'),
                trailing: r.isActive
                    ? TextButton(
                        onPressed: () => _cancel(r),
                        child: const Text('Cancel'))
                    : Text(r.total > 0
                        ? '\$${r.total.toStringAsFixed(2)}'
                        : ''),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

/// Form to create a roadside request.
class RoadsideRequestForm extends StatefulWidget {
  const RoadsideRequestForm({super.key});

  @override
  State<RoadsideRequestForm> createState() => _RoadsideRequestFormState();
}

class _RoadsideRequestFormState extends State<RoadsideRequestForm> {
  String _service = _services.first.$1;
  final _place = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _vehicle = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _place.dispose();
    _lat.dispose();
    _lng.dispose();
    _vehicle.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) {
      showInfo(context, 'Enter a valid latitude and longitude.');
      return;
    }
    setState(() => _busy = true);
    try {
      // The free-text vehicle field maps loosely to make/model.
      final parts = _vehicle.text.trim().split(' ');
      await api.roadside.create(
        service: _service,
        latitude: lat,
        longitude: lng,
        placeName: _place.text.trim().isEmpty ? null : _place.text.trim(),
        vehicleMake: parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : null,
        vehicleModel:
            parts.length > 1 ? parts.sublist(1).join(' ') : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) {
        showInfo(context, 'Request submitted');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request help')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('What do you need?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _services)
                ChoiceChip(
                  avatar: Icon(s.$3, size: 18),
                  label: Text(s.$2),
                  selected: _service == s.$1,
                  onSelected: (_) => setState(() => _service = s.$1),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _place,
            decoration: const InputDecoration(
              labelText: 'Location description',
              hintText: 'e.g. Highway 401 near exit 12',
              prefixIcon: Icon(Icons.place_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Latitude', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lng,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: 'Longitude', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _vehicle,
            decoration: const InputDecoration(
              labelText: 'Vehicle (make & model)',
              prefixIcon: Icon(Icons.directions_car_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes for the helper (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Submit request'),
          ),
        ],
      ),
    );
  }
}
