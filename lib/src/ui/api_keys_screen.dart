import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';

String _str(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return fallback;
}

/// Manage Developer API keys (create, list, revoke).
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  late Future<List<Map<String, dynamic>>> _keys;

  @override
  void initState() {
    super.initState();
    _keys = api.auth.listApiKeys();
  }

  Future<void> _reload() async {
    setState(() => _keys = api.auth.listApiKeys());
    await _keys;
  }

  Future<void> _create() async {
    final label = await showDialog<String>(
      context: context,
      builder: (_) => const _NewKeyDialog(),
    );
    if (label == null) return;
    try {
      final result = await api.auth.createApiKey(label: label.isEmpty ? null : label);
      // The full key value is only returned once on creation.
      final value = _str(result, ['key', 'api_key', 'token', 'secret', 'value']);
      if (mounted && value.isNotEmpty) await _showKey(value);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _showKey(String value) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Your new API key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Copy it now — it won't be shown again."),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(value,
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                Navigator.pop(context);
                showInfo(context, 'Copied to clipboard');
              },
              child: const Text('Copy'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      );

  Future<void> _revoke(String id, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revoke key?'),
        content: Text('"$label" will stop working immediately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.auth.revokeApiKey(id);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer API')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New key'),
      ),
      body: MaxWidth(
        child: RefreshIndicator(
        onRefresh: _reload,
        child: AsyncList<Map<String, dynamic>>(
          future: _keys,
          loading: const ListSkeleton(),
          emptyMessage: 'No API keys.\nCreate one to use the OkaySpace API.',
          emptyIcon: Icons.vpn_key_outlined,
          builder: (context, items) => ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final k = items[i];
              final id = _str(k, ['id', 'key_id']);
              final label = _str(k, ['label', 'name'], 'Untitled key');
              final prefix = _str(k, ['prefix', 'masked', 'preview']);
              final created = _str(k, ['created_at']);
              return ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(label),
                subtitle: Text([
                  if (prefix.isNotEmpty) prefix,
                  if (created.isNotEmpty) created.split('T').first,
                ].join(' · ')),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  tooltip: 'Revoke',
                  onPressed: id.isEmpty ? null : () => _revoke(id, label),
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

class _NewKeyDialog extends StatefulWidget {
  const _NewKeyDialog();

  @override
  State<_NewKeyDialog> createState() => _NewKeyDialogState();
}

class _NewKeyDialogState extends State<_NewKeyDialog> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New API key'),
      content: TextField(
        controller: _label,
        autofocus: true,
        decoration: const InputDecoration(
            labelText: 'Label (e.g. "My script")',
            border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _label.text.trim()),
            child: const Text('Create')),
      ],
    );
  }
}
