import 'package:flutter/material.dart';

import '../core/cloudinary_api.dart';
import '../core/foursquare_api.dart';
import '../core/mapbox_api.dart';
import 'admin_settings_screen.dart';
import 'common.dart';
import 'wallet_screen.dart';

List<Map<String, dynamic>> _asMapList(dynamic data, [String? key]) {
  dynamic list = data;
  if (data is Map) {
    list = data[key] ??
        data['items'] ??
        data['posts'] ??
        data['services'] ??
        data['integrations'] ??
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

/// Admin · Test bot: simulates ad traffic so the wallet/analytics/earnings
/// flow can be verified without real users.
class AdminBotScreen extends StatefulWidget {
  const AdminBotScreen({super.key});

  @override
  State<AdminBotScreen> createState() => _AdminBotScreenState();
}

class _AdminBotScreenState extends State<AdminBotScreen> {
  late final Future<List<Map<String, dynamic>>> _posts =
      api.admin.botPosts().then((d) => _asMapList(d, 'posts'));
  String? _postId;
  final _views = TextEditingController(text: '100');
  final _clicks = TextEditingController(text: '10');
  final _likes = TextEditingController(text: '20');
  final _comments = TextEditingController(text: '5');
  Map<String, dynamic>? _result;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_views, _clicks, _likes, _comments]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    if (_postId == null) {
      showInfo(context, 'Pick a sponsored post first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await api.admin.runBot({
        'post_id': _postId,
        'views': int.tryParse(_views.text.trim()) ?? 0,
        'clicks': int.tryParse(_clicks.text.trim()) ?? 0,
        'likes': int.tryParse(_likes.text.trim()) ?? 0,
        'comments': int.tryParse(_comments.text.trim()) ?? 0,
      });
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: OkayAppBar(
        title: const Text('Admin · Test bot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Wallet',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
                'Simulates ad traffic — counters move like real traffic, but no '
                'real likes or comments are posted, and earnings are credited '
                'to you so you can verify the money flow.',
                style: TextStyle(color: scheme.outline, fontSize: 12.5)),
            const SizedBox(height: 12),
            const Text('Sponsored post',
                style: TextStyle(fontWeight: FontWeight.bold)),
            AsyncList<Map<String, dynamic>>(
              future: _posts,
              emptyMessage: 'No sponsored posts to test against.',
              emptyIcon: Icons.campaign_outlined,
              builder: (context, posts) => RadioGroup<String>(
                groupValue: _postId,
                onChanged: (v) => setState(() => _postId = v),
                child: Column(
                children: [
                  for (final p in posts)
                    RadioListTile<String>(
                      dense: true,
                      value: '${p['id'] ?? p['post_id']}',
                      title: Text('${p['text'] ?? p['title'] ?? 'Post'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${p['owner_name'] ?? p['author'] ?? ''} · '
                          '${p['views'] ?? 0} views · ${p['clicks'] ?? 0} clicks',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              for (final (label, c) in [
                ('Views', _views),
                ('Clicks', _clicks),
                ('Likes', _likes),
                ('Comments', _comments)
              ]) ...[
                Expanded(
                  child: TextField(
                    controller: c,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: label,
                        isDense: true,
                        border: const OutlineInputBorder()),
                  ),
                ),
                if (label != 'Comments') const SizedBox(width: 8),
              ],
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: const Text('Run bot'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'You earned \$${(num.tryParse('${_result!['earned'] ?? _result!['you_earned'] ?? 0}') ?? 0).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 6),
                      Text(
                          'Advertiser spend: \$${(num.tryParse('${_result!['spend'] ?? _result!['advertiser_spend'] ?? 0}') ?? 0).toStringAsFixed(2)}',
                          style: TextStyle(
                              color: scheme.outline, fontSize: 13)),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const WalletScreen())),
                        child: const Text('Check your wallet →'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Admin · Integrations: configuration health of every backend integration.
class AdminIntegrationsScreen extends StatefulWidget {
  const AdminIntegrationsScreen({super.key});

  @override
  State<AdminIntegrationsScreen> createState() =>
      _AdminIntegrationsScreenState();
}

class _AdminIntegrationsScreenState extends State<AdminIntegrationsScreen> {
  late Future<List<Map<String, dynamic>>> _list = _fetch(false);
  bool _issuesOnly = false;
  bool _testing = false;

  Future<List<Map<String, dynamic>>> _fetch(bool live, [String? only]) =>
      api.admin.integrations(live: live, only: only).then(_asMapList);

  Future<void> _runLive() async {
    setState(() {
      _testing = true;
      _list = _fetch(true);
    });
    try {
      await _list;
    } catch (_) {}
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Integrations')),
      body: MaxWidth(
        child: AsyncList<Map<String, dynamic>>(
          future: _list,
          emptyMessage: 'No integrations reported.',
          emptyIcon: Icons.extension_outlined,
          builder: (context, all) {
            final shown = _issuesOnly
                ? all
                    .where((i) =>
                        '${i['status']}' != 'ok' &&
                        '${i['status']}' != 'configured')
                    .toList()
                : all;
            final ok = all
                .where((i) =>
                    '${i['status']}' == 'ok' ||
                    '${i['status']}' == 'configured')
                .length;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Wrap, not Row: on phones the chips would squeeze the count
                // label into a one-character-per-line column.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('$ok/${all.length} configured',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    FilterChip(
                      label: const Text('Issues only'),
                      selected: _issuesOnly,
                      onSelected: (v) => setState(() => _issuesOnly = v),
                    ),
                    FilledButton(
                      onPressed: _testing ? null : _runLive,
                      child: Text(_testing ? 'Testing…' : 'Run live tests'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // SDKs compiled into this app build (set via CI secrets /
                // --dart-define, not backend env vars — so they're shown
                // here client-side, not in the backend's list below).
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('App SDKs (this build)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                            'Baked in at build time from GitHub/Codemagic '
                            'secrets. A redeploy is needed after adding one.',
                            style: TextStyle(
                                color: scheme.outline, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (name, set) in [
                              ('Mapbox', hasMapbox),
                              ('Cloudinary', hasCloudinary),
                              ('Foursquare', hasFoursquare),
                              (
                                'Stripe top-up link',
                                const String.fromEnvironment(
                                        'STRIPE_TOPUP_LINK')
                                    .isNotEmpty
                              ),
                            ])
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(
                                    set
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 14,
                                    color: set
                                        ? const Color(0xFF22C55E)
                                        : scheme.outline),
                                label: Text(
                                    '$name · ${set ? 'configured' : 'missing'}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                for (final i in shown)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                    '${i['name'] ?? i['key']}${i['required'] == true ? ' *' : ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: ('${i['status']}' == 'ok' ||
                                          '${i['status']}' == 'configured')
                                      ? const Color(0xFF22C55E)
                                          .withValues(alpha: 0.15)
                                      : scheme.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${i['status'] ?? 'unknown'}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: ('${i['status']}' == 'ok' ||
                                                '${i['status']}' ==
                                                    'configured')
                                            ? const Color(0xFF22C55E)
                                            : scheme.error)),
                              ),
                            ],
                          ),
                          if (i['summary'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${i['summary']}',
                                  style: TextStyle(
                                      color: scheme.outline, fontSize: 12)),
                            ),
                          if (i['latency_ms'] != null)
                            Text('Tested in ${i['latency_ms']} ms',
                                style: TextStyle(
                                    color: scheme.outline, fontSize: 11)),
                          if (i['env'] is List) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final e in (i['env'] as List))
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(
                                        (e is Map && e['set'] == true)
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        size: 14,
                                        color: (e is Map && e['set'] == true)
                                            ? const Color(0xFF22C55E)
                                            : scheme.outline),
                                    label: Text(
                                        e is Map ? '${e['key']}' : '$e',
                                        style:
                                            const TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                          ],
                          if (i['fix'] != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${i['fix']}',
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
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

/// Admin · Render hosting: operate the Render-hosted services.
class AdminRenderScreen extends StatefulWidget {
  const AdminRenderScreen({super.key});

  @override
  State<AdminRenderScreen> createState() => _AdminRenderScreenState();
}

class _AdminRenderScreenState extends State<AdminRenderScreen> {
  late Future<List<Map<String, dynamic>>> _services =
      api.admin.renderServices().then((d) => _asMapList(d, 'services'));

  Future<void> _reload() async {
    setState(() => _services =
        api.admin.renderServices().then((d) => _asMapList(d, 'services')));
    try {
      await _services;
    } catch (_) {}
  }

  Future<void> _op(BuildContext context, String title, String message,
      Future<void> Function() op,
      {bool destructive = false}) async {
    if (!await adminConfirm(context, title, message,
        action: title, destructive: destructive)) {
      return;
    }
    if (!context.mounted) return;
    try {
      await op();
      if (context.mounted) {
        showInfo(context, '$title requested');
        _reload();
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Admin · Render hosting')),
      body: MaxWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: AsyncList<Map<String, dynamic>>(
            future: _services,
            emptyMessage:
                'Render API not connected.\nSet RENDER_API_KEY on the backend.',
            emptyIcon: Icons.cloud_off_outlined,
            builder: (context, services) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final s in services)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: '${s['deploy_status'] ?? s['status']}'
                                          .contains('live')
                                      ? const Color(0xFF22C55E)
                                      : '${s['deploy_status'] ?? s['status']}'
                                              .contains('fail')
                                          ? scheme.error
                                          : const Color(0xFFF59E0B),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    '${s['name']}${s['is_this_app'] == true ? '  ·  this app' : ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          Text(
                              '${s['type'] ?? ''} · ${s['branch'] ?? ''} · ${s['deploy_status'] ?? s['status'] ?? ''}',
                              style: TextStyle(
                                  color: scheme.outline, fontSize: 12)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                                onPressed: () => _op(
                                    context,
                                    'Deploy',
                                    'Deploy ${s['name']} now?',
                                    () => api.admin
                                        .renderTriggerDeploy('${s['id']}')),
                                child: const Text('Deploy'),
                              ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                                onPressed: () => _op(
                                    context,
                                    'Clear cache & deploy',
                                    'Clear the build cache and deploy ${s['name']}?',
                                    () => api.admin.renderTriggerDeploy(
                                        '${s['id']}',
                                        clearCache: true)),
                                child: const Text('Clear cache & deploy'),
                              ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact),
                                onPressed: () => _op(
                                    context,
                                    'Restart',
                                    'Restart ${s['name']}?',
                                    () =>
                                        api.admin.renderRestart('${s['id']}')),
                                child: const Text('Restart'),
                              ),
                              if (s['suspended'] == true)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact),
                                  onPressed: () => _op(
                                      context,
                                      'Resume',
                                      'Resume ${s['name']}?',
                                      () => api.admin
                                          .renderResume('${s['id']}')),
                                  child: const Text('Resume'),
                                )
                              else
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: scheme.error),
                                  onPressed: () => _op(
                                      context,
                                      'Suspend',
                                      'Suspend ${s['name']}? It stops serving until resumed.',
                                      () => api.admin
                                          .renderSuspend('${s['id']}'),
                                      destructive: true),
                                  child: const Text('Suspend'),
                                ),
                            ],
                          ),
                          _EnvVarsSection(serviceId: '${s['id']}'),
                          _DeploysSection(serviceId: '${s['id']}'),
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

/// Collapsible env-var editor for one Render service.
class _EnvVarsSection extends StatefulWidget {
  const _EnvVarsSection({required this.serviceId});

  final String serviceId;

  @override
  State<_EnvVarsSection> createState() => _EnvVarsSectionState();
}

class _EnvVarsSectionState extends State<_EnvVarsSection> {
  Future<List<Map<String, dynamic>>>? _vars;
  final Set<String> _revealed = {};

  void _open() {
    _vars ??= api.admin
        .renderEnvVars(widget.serviceId)
        .then((d) => _asMapList(d, 'env_vars'));
  }

  void _reload() {
    setState(() => _vars = api.admin
        .renderEnvVars(widget.serviceId)
        .then((d) => _asMapList(d, 'env_vars')));
  }

  Future<void> _set(String key, {String? current}) async {
    final value = await promptText(context,
        title: current == null ? 'Add $key' : 'Edit $key',
        hint: 'Value (saving triggers a redeploy)',
        action: 'Save');
    if (value == null || !mounted) return;
    try {
      await api.admin.renderSetEnv(widget.serviceId, key, value);
      if (mounted) {
        showInfo(context, '$key saved — redeploying');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Environment variables',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      onExpansionChanged: (open) {
        if (open) setState(_open);
      },
      children: [
        if (_vars == null)
          const SizedBox.shrink()
        else
          AsyncList<Map<String, dynamic>>(
            future: _vars!,
            emptyMessage: 'No environment variables.',
            emptyIcon: Icons.code,
            builder: (context, vars) => Column(
              children: [
                for (final v in vars)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${v['key']}',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13)),
                    subtitle: Text(
                        _revealed.contains('${v['key']}')
                            ? '${v['value']}'
                            : '••••••••',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                              _revealed.contains('${v['key']}')
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18),
                          onPressed: () => setState(() =>
                              _revealed.contains('${v['key']}')
                                  ? _revealed.remove('${v['key']}')
                                  : _revealed.add('${v['key']}')),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () =>
                              _set('${v['key']}', current: '${v['value']}'),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: scheme.error),
                          onPressed: () async {
                            if (!await adminConfirm(
                                context,
                                'Delete ${v['key']}',
                                'Deleting triggers a redeploy.',
                                action: 'Delete',
                                destructive: true)) {
                              return;
                            }
                            try {
                              await api.admin.renderDeleteEnv(
                                  widget.serviceId, '${v['key']}');
                              if (context.mounted) _reload();
                            } catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add variable'),
                  onPressed: () async {
                    final key = await promptText(context,
                        title: 'New variable', hint: 'KEY', action: 'Next');
                    if (key == null || key.trim().isEmpty || !mounted) return;
                    await _set(key.trim().toUpperCase());
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Collapsible recent-deploys list for one Render service.
class _DeploysSection extends StatefulWidget {
  const _DeploysSection({required this.serviceId});

  final String serviceId;

  @override
  State<_DeploysSection> createState() => _DeploysSectionState();
}

class _DeploysSectionState extends State<_DeploysSection> {
  Future<List<Map<String, dynamic>>>? _deploys;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Recent deploys',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      onExpansionChanged: (open) {
        if (open) {
          setState(() => _deploys ??= api.admin
              .renderDeploys(widget.serviceId)
              .then((d) => _asMapList(d, 'deploys')));
        }
      },
      children: [
        if (_deploys == null)
          const SizedBox.shrink()
        else
          AsyncList<Map<String, dynamic>>(
            future: _deploys!,
            emptyMessage: 'No deploys yet.',
            emptyIcon: Icons.rocket_launch_outlined,
            builder: (context, deploys) => Column(
              children: [
                for (final d in deploys)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${d['commit_message'] ?? d['message'] ?? 'Deploy'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '${d['status'] ?? ''} · ${'${d['commit_id'] ?? d['commit'] ?? ''}'.split('').take(7).join()} · ${d['created_at'] ?? ''}',
                        style:
                            TextStyle(color: scheme.outline, fontSize: 11)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
