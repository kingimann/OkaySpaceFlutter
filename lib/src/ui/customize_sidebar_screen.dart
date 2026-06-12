import 'package:flutter/material.dart';

import 'common.dart';

/// Lets the user choose which destinations appear in the sidebar (drawer).
/// Reorder, remove, and add from the rest.
class CustomizeSidebarScreen extends StatelessWidget {
  const CustomizeSidebarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Customize sidebar')),
      body: MaxWidth(
        child: ValueListenableBuilder<List<String>>(
          valueListenable: sidebarController,
          builder: (context, ids, _) {
            final available =
                kAllSidebarDests.where((d) => !ids.contains(d.id)).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('In your sidebar (${ids.length}/${SidebarController.maxItems})',
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text('Drag to reorder.',
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
                const SizedBox(height: 8),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // onReorderItem pre-adjusts the destination index for the
                  // removed item, unlike the deprecated onReorder.
                  onReorderItem: (oldI, newI) {
                    final list = [...ids];
                    list.insert(newI, list.removeAt(oldI));
                    sidebarController.set(list);
                  },
                  children: [
                    for (final id in ids)
                      Card(
                        key: ValueKey(id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: _icon(sidebarDestById(id)),
                          title: Text(sidebarDestById(id).label),
                          trailing: IconButton(
                            icon: Icon(Icons.remove_circle_outline,
                                color: scheme.error),
                            onPressed: ids.length > SidebarController.minItems
                                ? () => sidebarController.remove(id)
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
                if (sidebarController.isFull)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Remove an item to add another (max 5).',
                        style: TextStyle(color: scheme.outline)),
                  )
                else if (available.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Everything is in your sidebar.',
                        style: TextStyle(color: scheme.outline)),
                  )
                else
                  for (final d in available)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: _icon(d),
                        title: Text(d.label),
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle_outline,
                              color: scheme.primary),
                          onPressed: () => sidebarController.add(d.id),
                        ),
                        onTap: () => sidebarController.add(d.id),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _icon(SidebarDest d) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: d.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(d.icon, color: d.color, size: 22),
      );
}
