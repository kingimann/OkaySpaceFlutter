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

  /// Each person's share of the total (null until the form is valid).
  num? get _share {
    final total = _total;
    if (total == null || total <= 0 || _people.isEmpty) return null;
    return total / (_people.length + (_includeMe ? 1 : 0));
  }

  Future<void> _send() async {
    final share = _share;
    if (share == null) {
      showInfo(context, 'Pick people and a valid total.');
      return;
    }
    final note = _note.text.trim();
    setState(() => _busy = true);
    var sent = 0;
    try {
      for (final p in _people) {
        await api.wallet.requestMoney(
          toUserId: p.userId,
          amount: num.parse(share.toStringAsFixed(2)),
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
    final share = _share;

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
            if (share != null) ...[
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
                        '${share.toStringAsFixed(2)} each · ${_people.length} '
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
              onPressed: _busy || share == null ? null : _send,
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
