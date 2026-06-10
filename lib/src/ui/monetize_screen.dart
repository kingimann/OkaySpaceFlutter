import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Publisher network: register sites, view ad earnings and copy the embed
/// snippet (§10 `/monetize`), backed by the `/pub/sites` endpoints.
class MonetizeScreen extends StatefulWidget {
  const MonetizeScreen({super.key});

  @override
  State<MonetizeScreen> createState() => _MonetizeScreenState();
}

class _MonetizeScreenState extends State<MonetizeScreen> {
  late Future<List<PubSite>> _sites = api.monetize.sites();

  Future<void> _reload() async {
    setState(() => _sites = api.monetize.sites());
    await _sites;
  }

  Future<void> _add() async {
    final name = await promptText(context, title: 'Site name', action: 'Next');
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    final domain =
        await promptText(context, title: 'Domain', hint: 'example.com');
    try {
      await api.monetize.createSite(name: name.trim(), domain: domain?.trim());
      if (mounted) {
        showInfo(context, 'Site registered');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(PubSite s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove site?'),
        content: Text('Stop serving ads on "${s.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.monetize.deleteSite(s.id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Monetize'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Register site',
            onPressed: _add,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<PubSite>>(
          future: _sites,
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
            final sites = snap.data ?? const <PubSite>[];
            if (sites.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  CenteredMessage(
                    message:
                        'Register a site to earn from OkaySpace ads.\nTap + to add one.',
                    icon: Icons.monetization_on_outlined,
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final s in sites)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  if (s.domain.isNotEmpty)
                                    Text(s.domain,
                                        style:
                                            TextStyle(color: scheme.outline)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: scheme.error),
                              onPressed: () => _delete(s),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _stat('Earned',
                                '\$${s.earned.toStringAsFixed(2)}', scheme),
                            _stat('Impressions',
                                formatCount(s.impressions), scheme),
                            _stat('Clicks', formatCount(s.clicks), scheme),
                            _stat('CTR',
                                '${(s.ctr * 100).toStringAsFixed(1)}%', scheme),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(s.embedSnippet,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy embed'),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: s.embedSnippet));
                              showInfo(context, 'Embed snippet copied');
                            },
                          ),
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

  Widget _stat(String label, String value, ColorScheme scheme) => Expanded(
        child: Column(
          children: [
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: scheme.outline, fontSize: 11)),
          ],
        ),
      );
}
