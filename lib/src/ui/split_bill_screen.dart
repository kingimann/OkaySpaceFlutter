import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Split a bill: pick several people, enter the total, and a money request
/// for each person's even share goes out to all of them.
class SplitBillScreen extends StatefulWidget {
  const SplitBillScreen({super.key});

  @override
  State<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends State<SplitBillScreen> {
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  Future<List<PublicUser>>? _results;
  final List<PublicUser> _people = [];

  /// When true the bill is divided by people + me; I just don't get a request.
  bool _includeMe = true;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _runSearch() {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = api.users.search(q));
  }

  num? get _total => num.tryParse(_amount.text.trim());

  /// Each person's share in cents, allocated so the shares sum exactly to
  /// the total: everyone gets the floor, and the leftover cents go one each
  /// to the first few people. Empty until the form is valid.
  List<int> get _shareCents {
    final total = _total;
    if (total == null || total <= 0 || _people.isEmpty) return const [];
    final n = _people.length + (_includeMe ? 1 : 0);
    final totalCents = (total * 100).round();
    final base = totalCents ~/ n;
    final extra = totalCents % n;
    return [
      for (var i = 0; i < _people.length; i++) base + (i < extra ? 1 : 0),
    ];
  }

  Future<void> _send() async {
    final shares = _shareCents;
    if (shares.isEmpty) {
      showInfo(context, 'Pick people and a valid total.');
      return;
    }
    final note = _note.text.trim();
    setState(() => _busy = true);
    var sent = 0;
    try {
      for (var i = 0; i < _people.length; i++) {
        await api.wallet.requestMoney(
          toUserId: _people[i].userId,
          amount: shares[i] / 100,
          note: note.isEmpty ? 'Bill split' : note,
        );
        sent++;
      }
      if (mounted) {
        showInfo(context, 'Requested from $sent people');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        // Partial sends can happen; say how far it got.
        showError(
            context, sent > 0 ? '$sent of ${_people.length} sent — $e' : e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shares = _shareCents;
    // Shares can differ by a cent; show the range when they do.
    final shareLabel = shares.isEmpty
        ? ''
        : shares.first == shares.last
            ? (shares.first / 100).toStringAsFixed(2)
            : '${(shares.last / 100).toStringAsFixed(2)}–${(shares.first / 100).toStringAsFixed(2)}';

    return Scaffold(
      appBar: const OkayAppBar(title: Text('Split a bill')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Total amount',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include my share'),
              subtitle: const Text(
                  'Divide the total by everyone including me',
                  style: TextStyle(fontSize: 12)),
              value: _includeMe,
              onChanged: (v) => setState(() => _includeMe = v),
            ),
            if (_people.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _people)
                    InputChip(
                      avatar: Avatar(url: p.picture, name: p.name, radius: 12),
                      label: Text(p.name),
                      onDeleted: () => setState(() => _people.remove(p)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Add people',
                prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _runSearch),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_results != null)
              FutureBuilder<List<PublicUser>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final users = (snapshot.data ?? const <PublicUser>[])
                      .where((u) =>
                          u.userId != currentUserId &&
                          !_people.any((p) => p.userId == u.userId))
                      .toList();
                  if (users.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No matches.')));
                  }
                  return Column(children: [
                    for (final u in users)
                      ListTile(
                        leading: Avatar(url: u.picture, name: u.name),
                        title: Text(u.name),
                        subtitle: u.username != null ? Text(u.handle) : null,
                        trailing: const Icon(Icons.add),
                        onTap: () => setState(() {
                          _people.add(u);
                          _results = null;
                          _search.clear();
                        }),
                      ),
                  ]);
                },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. Dinner on Friday',
                  border: OutlineInputBorder()),
            ),
            if (shares.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.call_split, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$shareLabel each · ${_people.length} '
                        'request${_people.length == 1 ? '' : 's'}'
                        '${_includeMe ? ' (your share stays with you)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy || shares.isEmpty ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.call_split),
              label: const Text('Send requests'),
            ),
          ],
        ),
      ),
    );
  }
}
