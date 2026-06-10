import 'package:flutter/material.dart';

import 'common.dart';

/// Lists third-party apps with access to the account and lets the user revoke
/// them (§12 `/connected-apps`), backed by `oauth.connections` / `revokeConnection`.
class ConnectedAppsScreen extends StatefulWidget {
  const ConnectedAppsScreen({super.key});

  @override
  State<ConnectedAppsScreen> createState() => _ConnectedAppsScreenState();
}

class _ConnectedAppsScreenState extends State<ConnectedAppsScreen> {
  late Future<List<Map<String, dynamic>>> _apps = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await api.oauth.connections();
    final list = data is Map
        ? (data['connections'] ?? data['apps'] ?? data['items'] ?? data['data'])
        : data;
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> _reload() async {
    setState(() => _apps = _load());
    await _apps;
  }

  String _s(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return '';
  }

  Future<void> _revoke(Map<String, dynamic> app) async {
    final clientId = _s(app, ['client_id', 'clientId', 'id']);
    final name = _s(app, ['name', 'app_name', 'client_name']);
    if (clientId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Revoke access?'),
        content: Text('$name will no longer have access to your account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.oauth.revokeConnection(clientId);
      if (mounted) {
        showInfo(context, 'Access revoked');
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
      appBar: const OkayAppBar(title: Text('Connected apps')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _apps,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const ListSkeleton();
            }
            if (snap.hasError) {
              return CenteredMessage(
                  message: messageFor(snap.error),
                  icon: Icons.error_outline,
                  onRetry: _reload);
            }
            final apps = snap.data ?? const [];
            if (apps.isEmpty) {
              return const CenteredMessage(
                  message: 'No apps have access to your account.',
                  icon: Icons.apps_outlined);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = apps[i];
                final name = _s(a, ['name', 'app_name', 'client_name']);
                final scopes = _s(a, ['scopes', 'scope']);
                final logo = _s(a, ['logo', 'icon', 'logo_url']);
                return ListTile(
                  leading: logo.isEmpty
                      ? CircleAvatar(
                          backgroundColor: scheme.surfaceContainerHighest,
                          child: const Icon(Icons.extension_outlined))
                      : CircleAvatar(backgroundImage: NetworkImage(logo)),
                  title: Text(name.isEmpty ? 'App' : name),
                  subtitle: scopes.isEmpty
                      ? null
                      : Text('Access: ${scopes.replaceAll(',', ', ')}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                    onPressed: () => _revoke(a),
                    child: Text('Revoke',
                        style: TextStyle(color: scheme.error)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
