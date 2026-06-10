import 'package:flutter/material.dart';

import 'common.dart';
import 'feed_screen.dart';
import 'marketplace_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';

/// The signed-in app shell: a floating pill bottom navigation over the tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    loadCurrentUserId();
  }

  static const _items = <(IconData, IconData)>[
    (Icons.home_outlined, Icons.home),
    (Icons.play_circle_outline, Icons.play_circle),
    (Icons.chat_bubble_outline, Icons.chat_bubble),
    (Icons.storefront_outlined, Icons.storefront),
    (Icons.person_outline, Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const FeedScreen(),
      const ReelsScreen(),
      const MessagesScreen(),
      const MarketplaceScreen(),
      MyProfileScreen(onSignedOut: widget.onSignedOut),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _FloatingNav(
        index: _index,
        items: _items,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// A floating, pill-shaped navigation bar; the selected item sits in a teal
/// capsule (mirrors okayspace.ca).
class _FloatingNav extends StatelessWidget {
  const _FloatingNav(
      {required this.index, required this.items, required this.onTap});

  final int index;
  final List<(IconData, IconData)> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(28, 0, 28, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < items.length; i++)
              _NavItem(
                selected: i == index,
                icon: i == index ? items[i].$2 : items[i].$1,
                onTap: () => onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.selected, required this.icon, required this.onTap});

  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            icon,
            color: selected ? Colors.white : scheme.outline,
            size: 24,
          ),
        ),
      ),
    );
  }
}
