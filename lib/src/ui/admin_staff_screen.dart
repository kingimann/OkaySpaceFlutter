import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';

import 'admin_settings_screen.dart';
import 'common.dart';

List<Map<String, dynamic>> _asMapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ??
        data['items'] ??
        data['verifications'] ??
        data['calls'] ??
        data['tickets'] ??
        data['results'];
  }
  if (list is List) {
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

String _s(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return fallback;
}

void _lightbox(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(child: InteractiveViewer(child: Image.network(url))),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Staff · Roadside verifications: manual review of document submissions.
class AdminRoadsideScreen extends StatefulWidget {
  const AdminRoadsideScreen({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  State<AdminRoadsideScreen> createState() => _AdminRoadsideScreenState();
}

class _AdminRoadsideScreenState extends State<AdminRoadsideScreen> {
  late Future<List<Map<String, dynamic>>> _items = _fetch();

  Future<List<Map<String, dynamic>>> _fetch() =>
      api.admin.roadsideVerifications().then(_asMapList);

  Future<void> _reload() async {
    setState(() => _items = _fetch());
    try {
      await _items;
    } catch (_) {}
  }

  Future<void> _decide(String id, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await promptText(context,
          title: 'Reject verification',
          hint: 'Reason (shown to the member)',
          action: 'Reject');
      if (reason == null || !mounted) return;
    }
    try {
      await api.admin.decideRoadsideVerification(id, {
        'approved': approve,
        if (reason != null) 'reason': reason,
      });
      if (mounted) {
        showInfo(context, approve ? 'Approved' : 'Rejected');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Roadside verifications'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.call_outlined),
              tooltip: 'Roadside calls',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminRoadsideCallsScreen())),
            ),
        ],
      ),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _items,
            emptyMessage: 'No pending verifications.',
            emptyIcon: Icons.fact_check_outlined,
            builder: (context, items) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final v in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Avatar(
                                  url: _s(v, ['picture', 'avatar']).isEmpty
                                      ? null
                                      : _s(v, ['picture', 'avatar']),
                                  name: _s(v, ['name', 'user_name'], 'User')),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(_s(v, ['name', 'user_name'], 'User'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(_s(v, ['email']),
                                        style: TextStyle(
                                            color: scheme.outline,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_s(v, ['vehicle']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Vehicle: ${_s(v, ['vehicle'])}'),
                            ),
                          if (_s(v, ['note']).isNotEmpty)
                            Text('Note: ${_s(v, ['note'])}',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 13)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final (label, key) in const [
                                ('Insurance', 'insurance_url'),
                                ('Ownership', 'ownership_url')
                              ])
                                if (_s(v, [key]).isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 10),
                                    child: Column(
                                      children: [
                                        InkWell(
                                          onTap: () => _lightbox(
                                              context, _s(v, [key])),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.network(
                                                _s(v, [key]),
                                                width: 90,
                                                height: 64,
                                                fit: BoxFit.cover),
                                          ),
                                        ),
                                        Text(label,
                                            style: const TextStyle(
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: scheme.error),
                                  onPressed: () =>
                                      _decide(_s(v, ['id']), false),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      _decide(_s(v, ['id']), true),
                                  child: const Text('Approve'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

/// Admin · Roadside calls: create, search, and bulk-erase service calls.
class AdminRoadsideCallsScreen extends StatefulWidget {
  const AdminRoadsideCallsScreen({super.key});

  @override
  State<AdminRoadsideCallsScreen> createState() =>
      _AdminRoadsideCallsScreenState();
}

class _AdminRoadsideCallsScreenState extends State<AdminRoadsideCallsScreen> {
  late Future<List<Map<String, dynamic>>> _calls = _fetch();
  final _date = TextEditingController();
  final _callNo = TextEditingController();

  /// Client-side service filter ('' = all).
  String _serviceFilter = '';

  Future<List<Map<String, dynamic>>> _fetch({String? date, String? callNo}) =>
      api.admin
          .roadsideCalls(date: date, callNumber: callNo)
          .then(_asMapList);

  void _search() => setState(() => _calls = _fetch(
        date: _date.text.trim().isEmpty ? null : _date.text.trim(),
        callNo: _callNo.text.trim().isEmpty ? null : _callNo.text.trim(),
      ));

  @override
  void dispose() {
    _date.dispose();
    _callNo.dispose();
    super.dispose();
  }

  Future<void> _erase({required bool testOnly}) async {
    if (!await adminConfirm(
        context,
        testOnly ? 'Erase test calls' : 'Erase ALL calls',
        testOnly
            ? 'Removes every call created as a test.'
            : 'Removes every roadside call, real and test. This cannot be undone.',
        action: 'Erase',
        destructive: true)) {
      return;
    }
    try {
      await api.admin.eraseRoadsideCalls(testOnly: testOnly);
      if (mounted) {
        showInfo(context, 'Erased');
        _search();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _create({required bool isTest}) async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => AdminRoadsideCallFormScreen(isTest: isTest)));
    if (created == true && mounted) _search();
  }

  /// Copies the visible calls to the clipboard as CSV.
  Future<void> _exportCsv() async {
    final calls = await _calls.catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted || calls.isEmpty) {
      if (mounted) showInfo(context, 'Nothing to export.');
      return;
    }
    String esc(String v) => '"${v.replaceAll('"', '""')}"';
    final rows = [
      'call_number,service,status,is_test,caller,helper,place,destination,price,created_at',
      for (final c in calls)
        [
          esc(_s(c, ['call_number', 'number'])),
          esc(_s(c, ['service'])),
          esc(_s(c, ['status'])),
          '${c['is_test'] == true}',
          esc(_s(c, ['caller_name', 'requester_name'])),
          esc(_s(c, ['helper_name'])),
          esc(_s(c, ['place', 'address'])),
          esc(_s(c, ['destination', 'dest_name'])),
          esc(_s(c, ['price', 'amount'])),
          esc(_s(c, ['created_at'])),
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (mounted) showInfo(context, 'Copied ${calls.length} calls as CSV');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Roadside calls')),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _date,
                      decoration: const InputDecoration(
                          labelText: 'Date (YYYY-MM-DD)',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _callNo,
                      decoration: const InputDecoration(
                          labelText: 'Call #',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.search), onPressed: _search),
                  IconButton(
                      icon: const Icon(Icons.download_outlined),
                      tooltip: 'Export CSV',
                      onPressed: _exportCsv),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                      label: const Text('Test call'),
                      onPressed: () => _create(isTest: true)),
                  ActionChip(
                      label: const Text('Real call'),
                      onPressed: () => _create(isTest: false)),
                  ActionChip(
                      label: const Text('Erase test calls'),
                      onPressed: () => _erase(testOnly: true)),
                  ActionChip(
                      label: Text('Erase all',
                          style: TextStyle(color: scheme.error)),
                      onPressed: () => _erase(testOnly: false)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (id, label) in const [
                      ('', 'All'),
                      ('tow', 'Tow'),
                      ('lockout', 'Lockout'),
                      ('battery', 'Battery'),
                      ('tire', 'Tire'),
                      ('fuel', 'Gas'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _serviceFilter == id,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) =>
                              setState(() => _serviceFilter = id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AsyncList<Map<String, dynamic>>(
                future: _calls,
                emptyMessage: 'No roadside calls.',
                emptyIcon: Icons.car_crash_outlined,
                builder: (context, all) {
                  final calls = _serviceFilter.isEmpty
                      ? all
                      : all
                          .where((c) =>
                              _s(c, ['service']).toLowerCase() ==
                              _serviceFilter)
                          .toList();
                  final open = calls
                      .where((c) => !const ['completed', 'cancelled', 'canceled']
                          .contains(_s(c, ['status']).toLowerCase()))
                      .length;
                  final tests =
                      calls.where((c) => c['is_test'] == true).length;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // At-a-glance stats for the visible set.
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            '${calls.length} call${calls.length == 1 ? '' : 's'} · $open open · $tests test',
                            style: TextStyle(
                                color: scheme.outline,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (final c in calls)
                        _CallCard(call: c, onChanged: _search),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One roadside call, with everything dispatch needs at a glance.
class _CallCard extends StatelessWidget {
  const _CallCard({required this.call, required this.onChanged});

  final Map<String, dynamic> call;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = call;
    final status = _s(c, ['status'], 'open');
    final photos = c['photos'] is List
        ? (c['photos'] as List).map((e) => '$e').where((u) => u.isNotEmpty)
        : const Iterable<String>.empty();
    final vehicle = [
      _s(c, ['vehicle_year']),
      _s(c, ['vehicle_color']),
      _s(c, ['vehicle_make']),
      _s(c, ['vehicle_model']),
      if (_s(c, ['vehicle_plate']).isNotEmpty)
        '· ${_s(c, ['vehicle_plate'])}',
    ].where((x) => x.isNotEmpty).join(' ');
    final payment = [
      _s(c, ['payment_method']),
      if (_s(c, ['price', 'amount']).isNotEmpty)
        '\$${_s(c, ['price', 'amount'])}',
      if (c['settled'] == true)
        'settled'
      else if (c['settled'] == false)
        'held',
    ].where((x) => x.isNotEmpty).join(' · ');

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: scheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 12.5, color: scheme.outline)),
              ),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '#${_s(c, ['call_number', 'number'], '?')} · ${_s(c, ['service'], 'call')}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (c['is_test'] == true)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('TEST',
                        style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      size: 19, color: scheme.error),
                  onPressed: () async {
                    if (!await adminConfirm(context, 'Delete call',
                        'Delete this roadside call?',
                        action: 'Delete', destructive: true)) {
                      return;
                    }
                    try {
                      await api.admin.deleteRoadsideCall(_s(c, ['id']));
                      if (context.mounted) onChanged();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ],
            ),
            line(
                Icons.person_outline,
                [
                  _s(c, ['caller_name', 'requester_name'], 'Caller'),
                  if (_s(c, ['caller_phone', 'phone']).isNotEmpty)
                    _s(c, ['caller_phone', 'phone']),
                ].join(' · ')),
            if (_s(c, ['helper_name']).isNotEmpty)
              line(
                  Icons.volunteer_activism_outlined,
                  [
                    'Helper: ${_s(c, ['helper_name'])}',
                    if (_s(c, ['helper_phone']).isNotEmpty)
                      _s(c, ['helper_phone']),
                  ].join(' · ')),
            if (vehicle.isNotEmpty)
              line(Icons.directions_car_outlined, vehicle),
            if (_s(c, ['place', 'address']).isNotEmpty)
              line(Icons.place_outlined, _s(c, ['place', 'address'])),
            if (_s(c, ['destination', 'dest_name']).isNotEmpty)
              line(Icons.flag_outlined,
                  'Drop-off: ${_s(c, ['destination', 'dest_name'])}'),
            if (_s(c, ['note', 'notes']).isNotEmpty)
              line(Icons.notes, _s(c, ['note', 'notes'])),
            if (payment.isNotEmpty) line(Icons.attach_money, payment),
            line(
                Icons.schedule,
                [
                  'created ${_s(c, ['created_at']).split('T').first}',
                  if (_s(c, ['accepted_at']).isNotEmpty)
                    'accepted ${_s(c, ['accepted_at']).split('T').first}',
                  if (_s(c, ['completed_at']).isNotEmpty)
                    'completed ${_s(c, ['completed_at']).split('T').first}',
                ].join(' · ')),
            if (photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final url in photos.take(6))
                      InkWell(
                        onTap: () => _lightbox(context, url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(url,
                              width: 72, height: 54, fit: BoxFit.cover),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full call-creation form: service, caller, vehicle, price, notes, photos,
/// and optional coordinates (defaults to downtown Toronto).
class AdminRoadsideCallFormScreen extends StatefulWidget {
  const AdminRoadsideCallFormScreen({super.key, required this.isTest});

  final bool isTest;

  @override
  State<AdminRoadsideCallFormScreen> createState() =>
      _AdminRoadsideCallFormScreenState();
}

class _AdminRoadsideCallFormScreenState
    extends State<AdminRoadsideCallFormScreen> {
  String _service = 'tow';
  final _caller = TextEditingController();
  final _phone = TextEditingController();
  final _place = TextEditingController();
  final _year = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _busy = false;

  static const _callServices = [
    ('tow', 'Tow', Icons.local_shipping),
    ('lockout', 'Lockout', Icons.lock_outline),
    ('battery', 'Battery', Icons.battery_charging_full),
    ('tire', 'Tire', Icons.tire_repair),
    ('fuel', 'Gas', Icons.local_gas_station),
  ];

  @override
  void dispose() {
    for (final c in [
      _caller, _phone, _place, _year, _make, _model,
      _color, _plate, _price, _notes, _lat, _lng,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(
          maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
      for (final f in picked.take(6 - _photos.length)) {
        _photos.add(await f.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _submit() async {
    if (_caller.text.trim().isEmpty || _place.text.trim().isEmpty) {
      showInfo(context, 'Caller name and place are required.');
      return;
    }
    final price = num.tryParse(_price.text.trim());
    setState(() => _busy = true);
    try {
      final res = await api.admin.createRoadsideCall({
        'service': _service,
        'caller_name': _caller.text.trim(),
        if (_phone.text.trim().isNotEmpty)
          'caller_phone': _phone.text.trim(),
        'place': _place.text.trim(),
        if (_year.text.trim().isNotEmpty)
          'vehicle_year': _year.text.trim(),
        if (_make.text.trim().isNotEmpty)
          'vehicle_make': _make.text.trim(),
        if (_model.text.trim().isNotEmpty)
          'vehicle_model': _model.text.trim(),
        if (_color.text.trim().isNotEmpty)
          'vehicle_color': _color.text.trim(),
        if (_plate.text.trim().isNotEmpty)
          'vehicle_plate': _plate.text.trim(),
        if (price != null && price.isFinite) 'price': price,
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        // Defaults to downtown Toronto when not provided (per spec).
        'latitude': double.tryParse(_lat.text.trim()) ?? 43.6532,
        'longitude': double.tryParse(_lng.text.trim()) ?? -79.3832,
        if (_photos.isNotEmpty)
          'photos': [
            for (final b in _photos)
              'data:image/jpeg;base64,${base64Encode(b)}',
          ],
        'is_test': widget.isTest,
      });
      if (mounted) {
        showInfo(
            context,
            widget.isTest
                ? 'Test call created'
                : 'Call #${res['call_number'] ?? res['number'] ?? '?'} created');
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
    final scheme = Theme.of(context).colorScheme;
    Widget two(TextEditingController a, String la, TextEditingController b,
            String lb) =>
        Row(children: [
          Expanded(
            child: TextField(
                controller: a,
                decoration: InputDecoration(
                    labelText: la,
                    isDense: true,
                    border: const OutlineInputBorder())),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
                controller: b,
                decoration: InputDecoration(
                    labelText: lb,
                    isDense: true,
                    border: const OutlineInputBorder())),
          ),
        ]);

    return Scaffold(
      appBar: OkayAppBar(
          title: Text(widget.isTest ? 'New test call' : 'New roadside call')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label, icon) in _callServices)
                  ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _service == id,
                    onSelected: (_) => setState(() => _service = id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            two(_caller, 'Caller name *', _phone, 'Phone'),
            const SizedBox(height: 10),
            TextField(
                controller: _place,
                decoration: const InputDecoration(
                    labelText: 'Place / address *',
                    isDense: true,
                    border: OutlineInputBorder())),
            const SizedBox(height: 14),
            Text('VEHICLE',
                style: TextStyle(
                    color: scheme.outline,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6)),
            const SizedBox(height: 8),
            two(_year, 'Year', _make, 'Make'),
            const SizedBox(height: 10),
            two(_model, 'Model', _color, 'Color'),
            const SizedBox(height: 10),
            two(_plate, 'Plate', _price, 'Price (\$)'),
            const SizedBox(height: 10),
            TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notes',
                    isDense: true,
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            two(_lat, 'Latitude (optional)', _lng, 'Longitude (optional)'),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_photos[i],
                            width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: InkWell(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: const CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close,
                                  size: 12, color: Colors.white)),
                        ),
                      ),
                    ]),
                  ),
                if (_photos.length < 6)
                  OutlinedButton.icon(
                    onPressed: _addPhotos,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text('Photos (${_photos.length}/6)'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(widget.isTest ? 'Create test call' : 'Create call'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Staff · Support queue: tickets across the platform, filterable by status.
class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  String _filter = 'open';
  late Future<List<Map<String, dynamic>>> _tickets = _fetch();

  /// Selected ticket ids while in bulk-select mode (long-press to start).
  final Set<String> _selected = {};
  bool _bulkBusy = false;

  Future<void> _bulkSetStatus(String status) async {
    final ids = _selected.toList();
    setState(() => _bulkBusy = true);
    var done = 0;
    try {
      for (final id in ids) {
        await api.support.setStatus(id, status);
        done++;
      }
      if (mounted) showInfo(context, 'Marked $done $status');
    } catch (e) {
      if (mounted) {
        showError(context, done > 0 ? '$done of ${ids.length} updated — $e' : e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _bulkBusy = false;
          _selected.clear();
        });
        _reload();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetch() => api.admin
      .supportTickets(status: _filter == 'all' ? null : _filter)
      .then(_asMapList);

  void _reload() => setState(() => _tickets = _fetch());

  Color _statusColor(String status, ColorScheme scheme) =>
      switch (status.toLowerCase()) {
        'open' => const Color(0xFF22C55E),
        'resolved' => const Color(0xFF3B82F6),
        'closed' => scheme.outline,
        _ => const Color(0xFFF59E0B),
      };

  Future<void> _open(Map<String, dynamic> t) async {
    final id = _s(t, ['id', 'ticket_id']);
    // Staff thread: show messages + reply + status controls.
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TicketThreadSheet(ticketId: id),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(_selected.isEmpty
            ? 'Support queue'
            : '${_selected.length} selected'),
        actions: [
          if (_selected.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.task_alt),
              tooltip: 'Mark resolved',
              onPressed: _bulkBusy ? null : () => _bulkSetStatus('resolved'),
            ),
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Mark closed',
              onPressed: _bulkBusy ? null : () => _bulkSetStatus('closed'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel selection',
              onPressed: () => setState(_selected.clear),
            ),
          ],
        ],
      ),
      body: MaxWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  for (final f in const ['open', 'all', 'resolved', 'closed'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f[0].toUpperCase() + f.substring(1)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() {
                          _filter = f;
                          // A new filter hides rows; keeping the old
                          // selection would bulk-act on invisible tickets.
                          _selected.clear();
                          _tickets = _fetch();
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncList<Map<String, dynamic>>(
                future: _tickets,
                emptyMessage: 'No tickets.',
                emptyIcon: Icons.support_agent_outlined,
                builder: (context, tickets) => ListView.separated(
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = tickets[i];
                    final status = _s(t, ['status'], 'open');
                    final id = _s(t, ['id', 'ticket_id']);
                    final when =
                        DateTime.tryParse(_s(t, ['created_at', 'updated_at']));
                    return ListTile(
                      selected: _selected.contains(id),
                      leading: _selected.isEmpty
                          ? null
                          : Checkbox(
                              value: _selected.contains(id),
                              onChanged: (_) => setState(() =>
                                  _selected.contains(id)
                                      ? _selected.remove(id)
                                      : _selected.add(id)),
                            ),
                      onLongPress: () =>
                          setState(() => _selected.add(id)),
                      title: Text(_s(t, ['subject'], 'Ticket'),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          [
                            _s(t, ['user_name', 'name']),
                            _s(t, ['category']),
                            if (when != null) shortAgo(when),
                          ].where((x) => x.isNotEmpty).join(' · ')),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(status, scheme)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(status,
                            style: TextStyle(
                                color: _statusColor(status, scheme),
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      onTap: _selected.isEmpty
                          ? () => _open(t)
                          : () => setState(() => _selected.contains(id)
                              ? _selected.remove(id)
                              : _selected.add(id)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Staff view of one ticket: thread, reply box, and status buttons.
class _TicketThreadSheet extends StatefulWidget {
  const _TicketThreadSheet({required this.ticketId});

  final String ticketId;

  @override
  State<_TicketThreadSheet> createState() => _TicketThreadSheetState();
}

class _TicketThreadSheetState extends State<_TicketThreadSheet> {
  late Future<Map<String, dynamic>> _ticket = api.support.ticket(widget.ticketId);
  final _reply = TextEditingController();
  bool _busy = false;

  void _reload() =>
      setState(() => _ticket = api.support.ticket(widget.ticketId));

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await api.support.reply(widget.ticketId, text);
      _reply.clear();
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await api.support.setStatus(widget.ticketId, status);
      if (mounted) {
        showInfo(context, 'Marked $status');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _ticket,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final t = snapshot.data!;
            final messages = _asMapList(t['messages'] ?? t['thread']);
            return Column(
              children: [
                ListTile(
                  title: Text(_s(t, ['subject'], 'Ticket'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${_s(t, ['user_name', 'name'])} · ${_s(t, ['status'], 'open')}'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final st in const ['open', 'resolved', 'closed'])
                        ActionChip(
                            label: Text('Mark $st'),
                            onPressed: () => _setStatus(st)),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final m in messages)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${_s(m, ['sender_name', 'from', 'author'], 'User')}'
                                  '${m['is_staff'] == true ? ' · staff' : ''}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.outline)),
                              Text(_s(m, ['message', 'text', 'body'])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _reply,
                          decoration: const InputDecoration(
                              hintText: 'Reply as staff…',
                              isDense: true,
                              border: OutlineInputBorder()),
                        ),
                      ),
                      IconButton(
                        icon: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
