import 'package:flutter/material.dart';

import 'common.dart';

/// Lets the user choose which destinations appear in the bottom navigation bar
/// (2–5 items; Feed is pinned). Reorder, remove, and add from the rest.
class CustomizeNavScreen extends StatelessWidget {
  const CustomizeNavScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Customize navigation')),
      body: MaxWidth(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: navController,
          builder: (context, ids, _) {
            final available =
                kAllNavDests.where((d) => !ids.contains(d.id)).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Your tabs (${ids.length}/${NavController.maxItems})',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text('Drag to reorder. Feed stays pinned.',
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
                const SizedBox(height: 8),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: true,
                  onReorder: (oldI, newI) {
                    final list = [...ids];
                    if (newI > oldI) newI -= 1;
                    list.insert(newI, list.removeAt(oldI));
                    navController.set(list);
                  },
                  children: [
                    for (final id in ids)
                      Card(
                        key: ValueKey(id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(navDestById(id).activeIcon,
                              color: scheme.primary),
                          title: Text(navDestById(id).label),
                          trailing: id == NavController.pinned
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(Icons.push_pin,
                                      size: 18, color: scheme.outline),
                                )
                              : IconButton(
                                  icon: Icon(Icons.remove_circle_outline,
                                      color: scheme.error),
                                  onPressed: ids.length > NavController.minItems
                                      ? () => navController.remove(id)
                                      : null,
                                ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Add more',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 8),
                if (available.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        navController.isFull
                            ? 'Remove a tab to add another (max 5).'
                            : 'All destinations are in your bar.',
                        style: TextStyle(color: scheme.outline)),
                  )
                else
                  for (final d in available)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(d.icon, color: scheme.onSurfaceVariant),
                        title: Text(d.label),
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle_outline,
                              color: navController.isFull
                                  ? scheme.outline
                                  : scheme.primary),
                          onPressed: navController.isFull
                              ? null
                              : () => navController.add(d.id),
                        ),
                        onTap: navController.isFull
                            ? null
                            : () => navController.add(d.id),
                      ),
                    ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => navController.set(
                        const ['feed', 'reels', 'messages', 'market', 'profile']),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset to default'),
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
