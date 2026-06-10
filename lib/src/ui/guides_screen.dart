import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../okayspace_api.dart';
import 'common.dart';

Color _guideColor(String hex, BuildContext context) {
  final h = hex.replaceFirst('#', '');
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return Theme.of(context).colorScheme.primary;
}

const _kGuideColors = <String>[
  '#00A884', '#10B981', '#06B6D4', '#6366F1', '#A855F7', '#F97316', '#F43F5E',
];

/// Saved places and curated guide collections (shareable when public).
class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key});

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  late Future<List<Place>> _places;
  late Future<List<Guide>> _guides;
  final _placeSearch = TextEditingController();
  String _placeQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _placeSearch.dispose();
    super.dispose();
  }

  void _load() {
    _places = api.guides.places();
    _guides = api.guides.guides();
  }

  Future<void> _reload() async {
    setState(_load);
    await _guides;
  }

  /// Searches a place by name (geocode) and saves the chosen result.
  Future<void> _addPlace() async {
    final query = await promptText(context,
        title: 'Save a place',
        hint: 'Search a place or address',
        action: 'Search');
    if (query == null) return;
    try {
      final results = await api.roadside.geocode(query);
      if (!mounted) return;
      if (results.isEmpty) {
        showInfo(context, 'No places found for “$query”.');
        return;
      }
      final r = results.first;
      final lat = r['lat'] ?? r['latitude'];
      final lng = r['lng'] ?? r['lon'] ?? r['longitude'];
      await api.guides.addPlace(
        title: '${r['name'] ?? r['display_name'] ?? query}',
        address: r['display_name'] != null ? '${r['display_name']}' : null,
        latitude: lat is num ? lat.toDouble() : double.tryParse('$lat'),
        longitude: lng is num ? lng.toDouble() : double.tryParse('$lng'),
      );
      if (mounted) {
        showInfo(context, 'Place saved');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _createGuide() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateGuideDialog(),
    );
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: const OkayAppBar(
            title: Text('Places & Guides'),
            bottom: TabBar(
              tabs: [Tab(text: 'Saved places'), Tab(text: 'Guides')],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              final tab = DefaultTabController.of(context).index;
              tab == 0 ? _addPlace() : _createGuide();
            },
            icon: const Icon(Icons.add),
            label: const Text('New'),
          ),
          body: MaxWidth(
            child: TabBarView(
              children: [_placesTab(), _guidesTab()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _placeSearch,
            onChanged: (v) => setState(() => _placeQuery = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search saved places',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _placeQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _placeSearch.clear();
                        setState(() => _placeQuery = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: AsyncList<Place>(
              future: _places,
              loading: const ListSkeleton(),
              emptyMessage: 'No saved places yet.\nTap “New” to save somewhere.',
              emptyIcon: Icons.place_outlined,
              builder: (context, all) {
                final items = _placeQuery.isEmpty
                    ? all
                    : all.where((p) {
                        final hay =
                            '${p.title} ${p.address ?? ''} ${p.category ?? ''} ${p.notes ?? ''}'
                                .toLowerCase();
                        return hay.contains(_placeQuery);
                      }).toList();
                if (items.isEmpty) {
                  return const CenteredMessage(
                      message: 'No matching places.', icon: Icons.search_off);
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 64),
                  itemBuilder: (context, i) {
                    final p = items[i];
                    return Dismissible(
              key: ValueKey(p.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) =>
                  api.guides.deletePlace(p.id).catchError((_) {}),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.14),
                  child: Icon(Icons.place,
                      color: Theme.of(context).colorScheme.primary),
                ),
                title: Text(p.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: p.address != null
                    ? Text(p.address!,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'guide') _addPlaceToGuide(p);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'guide', child: Text('Add to guide')),
                  ],
                ),
              ),
            );
          },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addPlaceToGuide(Place p) async {
    final guides = await _guides;
    if (!mounted) return;
    if (guides.isEmpty) {
      showInfo(context, 'Create a guide first.');
      return;
    }
    final guide = await showModalBottomSheet<Guide>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Add to guide',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final g in guides)
              ListTile(
                leading: CircleAvatar(
                    radius: 10, backgroundColor: _guideColor(g.color, context)),
                title: Text(g.name),
                trailing: g.placeIds.contains(p.id)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, g),
              ),
          ],
        ),
      ),
    );
    if (guide == null) return;
    try {
      await api.guides.addToGuide(guide.id, p.id);
      if (mounted) {
        showInfo(context, 'Added to ${guide.name}');
        _reload();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _guidesTab() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: AsyncList<Guide>(
        future: _guides,
        loading: const ListSkeleton(),
        emptyMessage: 'No guides yet.\nCreate one to organize your places.',
        emptyIcon: Icons.collections_bookmark_outlined,
        builder: (context, items) => ListView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 88),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final g = items[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _guideColor(g.color, context),
                  child: Text(g.icon.isNotEmpty ? g.icon : '📍',
                      style: const TextStyle(fontSize: 18)),
                ),
                title: Text(g.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${g.placeIds.length} place${g.placeIds.length == 1 ? '' : 's'}'
                    '${g.isPublic ? ' · Public' : ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GuideDetailScreen(guide: g)));
                  if (mounted) _reload();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A single guide: its places, public/share controls, and delete.
class GuideDetailScreen extends StatefulWidget {
  const GuideDetailScreen({super.key, required this.guide});

  final Guide guide;

  @override
  State<GuideDetailScreen> createState() => _GuideDetailScreenState();
}

class _GuideDetailScreenState extends State<GuideDetailScreen> {
  late Guide _guide = widget.guide;
  late final Future<List<Place>> _places = api.guides.places();

  Future<void> _togglePublic() async {
    try {
      final updated = await api.guides
          .updateGuide(_guide.id, {'is_public': !_guide.isPublic});
      if (mounted) {
        setState(() =>
            _guide = updated.id.isNotEmpty ? updated : _guide);
        showInfo(
            context, _guide.isPublic ? 'Guide is now public' : 'Guide is private');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _share() {
    final slug = _guide.slug;
    if (slug == null || slug.isEmpty) {
      showInfo(context, 'Make the guide public to get a share link.');
      return;
    }
    final url = 'https://okayspace.ca/guide/$slug';
    Clipboard.setData(ClipboardData(text: url));
    showInfo(context, 'Link copied: $url');
  }

  Future<void> _rename() async {
    final name = await promptText(context,
        title: 'Rename guide', action: 'Save', initial: _guide.name);
    if (name == null) return;
    try {
      final updated = await api.guides.updateGuide(_guide.id, {'name': name});
      if (mounted) {
        setState(() => _guide = updated.id.isNotEmpty ? updated : _guide);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete guide?'),
        content: Text('“${_guide.name}” will be removed. Places stay saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.guides.deleteGuide(_guide.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _removePlace(Place p) async {
    try {
      await api.guides.removeFromGuide(_guide.id, p.id);
      if (mounted) {
        setState(() => _guide = Guide(
              id: _guide.id,
              name: _guide.name,
              color: _guide.color,
              icon: _guide.icon,
              placeIds: List.of(_guide.placeIds)..remove(p.id),
              isPublic: _guide.isPublic,
              slug: _guide.slug,
              createdAt: _guide.createdAt,
              raw: _guide.raw,
            ));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(_guide.name),
        actions: [
          IconButton(
            icon: Icon(_guide.isPublic ? Icons.public : Icons.lock_outline),
            tooltip: _guide.isPublic ? 'Make private' : 'Make public',
            onPressed: _togglePublic,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share',
            onPressed: _share,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') _rename();
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete guide')),
            ],
          ),
        ],
      ),
      body: MaxWidth(
        child: FutureBuilder<List<Place>>(
          future: _places,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final inGuide = snap.data!
                .where((p) => _guide.placeIds.contains(p.id))
                .toList();
            if (inGuide.isEmpty) {
              return const CenteredMessage(
                  message:
                      'No places in this guide yet.\nAdd them from Saved places.',
                  icon: Icons.place_outlined);
            }
            return ListView.separated(
              itemCount: inGuide.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 64),
              itemBuilder: (context, i) {
                final p = inGuide[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _guideColor(_guide.color, context)
                        .withValues(alpha: 0.18),
                    child: Icon(Icons.place,
                        color: _guideColor(_guide.color, context)),
                  ),
                  title: Text(p.title),
                  subtitle: p.address != null
                      ? Text(p.address!,
                          maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove from guide',
                    onPressed: () => _removePlace(p),
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

class _CreateGuideDialog extends StatefulWidget {
  const _CreateGuideDialog();

  @override
  State<_CreateGuideDialog> createState() => _CreateGuideDialogState();
}

class _CreateGuideDialogState extends State<_CreateGuideDialog> {
  final _name = TextEditingController();
  String _color = _kGuideColors.first;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await api.guides.createGuide(name: _name.text.trim(), color: _color);
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
    return AlertDialog(
      title: const Text('New guide'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Coffee spots',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            children: [
              for (final c in _kGuideColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _guideColor(c, context),
                      shape: BoxShape.circle,
                      border: _color == c
                          ? Border.all(
                              color:
                                  Theme.of(context).colorScheme.onSurface,
                              width: 2.5)
                          : null,
                    ),
                    child: _color == c
                        ? const Icon(Icons.check,
                            size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}
