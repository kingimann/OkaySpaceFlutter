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

IconData _serviceIcon(String key) => _services
    .firstWhere((s) => s.$1 == key, orElse: () => ('', '', Icons.help_outline))
    .$3;

/// A status pill color for a roadside request.
Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
    case 'open':
      return const Color(0xFFF59E0B);
    case 'accepted':
    case 'enroute':
    case 'en_route':
    case 'arrived':
      return const Color(0xFF06B6D4);
    case 'completed':
      return const Color(0xFF22C55E);
    case 'cancelled':
    case 'canceled':
    case 'disputed':
      return const Color(0xFFF43F5E);
    default:
      return const Color(0xFF8696A0);
  }
}

/// Roadside assistance: tabbed view of your requests, nearby calls to help
/// with, requests you're helping, and history.
class RoadsideScreen extends StatefulWidget {
  const RoadsideScreen({super.key});

  @override
  State<RoadsideScreen> createState() => _RoadsideScreenState();
}

class _RoadsideScreenState extends State<RoadsideScreen> {
  // Default search origin until device location is available.
  static const _lat = 43.6532, _lng = -79.3832;

  late Future<List<RoadsideRequest>> _mine;
  late Future<List<RoadsideRequest>> _nearby;
  late Future<List<RoadsideRequest>> _helping;
  late Future<List<RoadsideRequest>> _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _mine = api.roadside.mine();
    _nearby = api.roadside.nearby(lat: _lat, lng: _lng, radiusKm: 50);
    _helping = api.roadside.helping();
    _history = api.roadside.history();
  }

  Future<void> _reload() async {
    setState(_load);
    await _mine;
  }

  Future<void> _request() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => const RoadsideRequestForm(),
    ));
    if (created == true) _reload();
  }

  Future<void> _open(RoadsideRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoadsideDetailScreen(requestId: r.id),
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: const OkayAppBar(
          title: Text('Roadside assistance'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'My requests'),
              Tab(text: 'Nearby'),
              Tab(text: 'Helping'),
              Tab(text: 'History'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _request,
          icon: const Icon(Icons.add_alert),
          label: const Text('Request help'),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [
              _list(_mine, 'No roadside requests.\nTap “Request help” if you’re stuck.'),
              _list(_nearby, 'No open requests nearby right now.'),
              _list(_helping, "You're not helping with any requests."),
              _list(_history, 'No past requests.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(Future<List<RoadsideRequest>> future, String empty) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<RoadsideRequest>(
        future: future,
        loading: const ListSkeleton(),
        emptyMessage: empty,
        emptyIcon: Icons.car_repair,
        builder: (context, items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = items[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _statusColor(r.status).withValues(alpha: 0.18),
                child: Icon(_serviceIcon(r.service),
                    color: _statusColor(r.status)),
              ),
              title: Text(_serviceLabel(r.service),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                if (r.placeName != null) r.placeName!,
                shortAgo(r.createdAt),
                if (r.distanceKm != null)
                  '${r.distanceKm!.toStringAsFixed(1)} km',
              ].join(' · ')),
              trailing: _StatusPill(status: r.status),
              onTap: () => _open(r),
            );
          },
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(
              color: c, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

/// Full request detail with the lifecycle actions appropriate to the viewer
/// (requester vs. helper) and the current status.
class RoadsideDetailScreen extends StatefulWidget {
  const RoadsideDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<RoadsideDetailScreen> createState() => _RoadsideDetailScreenState();
}

class _RoadsideDetailScreenState extends State<RoadsideDetailScreen> {
  late Future<RoadsideRequest> _req;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _req = api.roadside.get(widget.requestId);
  }

  Future<void> _do(Future<RoadsideRequest> Function() op, String ok) async {
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) {
        showInfo(context, ok);
        setState(() => _req = api.roadside.get(widget.requestId));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => const _ReviewDialog(),
    );
    if (result == null) return;
    _do(() => api.roadside.review(widget.requestId,
        rating: result.$1, text: result.$2.isEmpty ? null : result.$2),
        'Thanks for your review');
  }

  Future<void> _verify() async {
    final code = await promptText(context,
        title: 'Enter completion code',
        hint: '6-digit code from the helper',
        action: 'Verify');
    if (code == null) return;
    _do(() => api.roadside.verify(widget.requestId, code), 'Verified');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Request')),
      body: MaxWidth(
        child: FutureBuilder<RoadsideRequest>(
          future: _req,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final r = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          _statusColor(r.status).withValues(alpha: 0.18),
                      child: Icon(_serviceIcon(r.service),
                          color: _statusColor(r.status), size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_serviceLabel(r.service),
                              style: Theme.of(context).textTheme.titleLarge),
                          if (r.callNumber != null)
                            Text('Call #${r.callNumber}',
                                style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    _StatusPill(status: r.status),
                  ],
                ),
                const SizedBox(height: 16),
                _row(Icons.place_outlined, r.placeName ?? 'Location set'),
                if (r.vehicleMake != null || r.vehicleModel != null)
                  _row(Icons.directions_car_outlined,
                      [r.vehicleColor, r.vehicleMake, r.vehicleModel]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' ')),
                if (r.note != null && r.note!.isNotEmpty)
                  _row(Icons.notes, r.note!),
                if (r.total > 0)
                  _row(Icons.attach_money,
                      'Total \$${r.total.toStringAsFixed(2)}'),
                if (r.distanceKm != null)
                  _row(Icons.straighten,
                      '${r.distanceKm!.toStringAsFixed(1)} km away'),
                const SizedBox(height: 24),
                ..._actions(r),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );

  /// Lifecycle buttons depend on whether the request is mine, I'm helping,
  /// and the status.
  List<Widget> _actions(RoadsideRequest r) {
    final status = r.status.toLowerCase();
    final btns = <Widget>[];

    FilledButton big(String label, IconData icon, VoidCallback onTap,
            {Color? color}) =>
        FilledButton.icon(
          onPressed: _busy ? null : onTap,
          icon: Icon(icon),
          label: Text(label),
          style: color != null
              ? FilledButton.styleFrom(backgroundColor: color)
              : null,
        );

    if (r.mine) {
      if (r.isActive) {
        btns.add(big('Cancel request', Icons.cancel_outlined,
            () => _do(() => api.roadside.cancel(r.id), 'Cancelled'),
            color: Theme.of(context).colorScheme.error));
        btns.add(const SizedBox(height: 10));
        btns.add(OutlinedButton.icon(
          onPressed: _busy ? null : _verify,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Enter completion code'),
        ));
      }
      if (status == 'completed' && (r.canReview ?? false)) {
        btns.add(big('Leave a review', Icons.star_outline, _review));
      }
      if (r.canDispute ?? false) {
        btns.add(const SizedBox(height: 10));
        btns.add(OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _do(() => api.roadside.dispute(r.id), 'Dispute opened'),
          icon: const Icon(Icons.gavel_outlined),
          label: const Text('Open a dispute'),
        ));
      }
    } else {
      // Helper view.
      if (r.helping) {
        if (!r.enRoute) {
          btns.add(big("I'm on my way", Icons.directions_car,
              () => _do(() => api.roadside.enroute(r.id), 'Marked en route')));
        } else if (!r.arrived) {
          btns.add(big("I've arrived", Icons.flag,
              () => _do(() => api.roadside.arrived(r.id), 'Marked arrived')));
        } else {
          btns.add(const Text('Waiting for the requester to confirm…'));
        }
      } else if (status == 'pending' || status == 'open') {
        btns.add(big('Accept & help', Icons.volunteer_activism,
            () => _do(() => api.roadside.accept(r.id), 'You accepted'),
            color: const Color(0xFF22C55E)));
      }
    }

    if (btns.isEmpty) {
      btns.add(Center(
        child: Text('No actions available.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ));
    }
    return btns;
  }
}

/// A 1–5 star review with optional text.
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 5;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leave a review'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(i <= _rating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF59E0B)),
                ),
            ],
          ),
          TextField(
            controller: _text,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Comments (optional)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, (_rating, _text.text.trim())),
            child: const Text('Submit')),
      ],
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
      appBar: const OkayAppBar(title: Text('Request help')),
      body: MaxWidth(
        child: ListView(
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
      ),
    );
  }
}
