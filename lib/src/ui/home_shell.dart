import 'package:flutter/material.dart';

import 'common.dart';
import 'communities_screen.dart';
import 'feed_screen.dart';
import 'groups_screen.dart';
import 'guides_screen.dart';
import 'map_screen.dart';
import 'marketplace_screen.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';
import 'search_screen.dart';
import 'wallet_screen.dart';

/// The signed-in app shell: a customizable floating pill bottom navigation
/// over the selected destinations.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late String _currentId = navController.value.first;
  final Set<String> _visited = {};

  @override
  void initState() {
    super.initState();
    loadCurrentUserId();
    _visited.add(_currentId);
    homeTabSignal.addListener(_onTabSignal);
    navController.addListener(_onNavChanged);
  }

  @override
  void dispose() {
    homeTabSignal.removeListener(_onTabSignal);
    navController.removeListener(_onNavChanged);
    super.dispose();
  }

  void _onTabSignal() {
    final id = homeTabSignal.value;
    if (!navController.value.contains(id)) return;
    setState(() {
      _currentId = id;
      _visited.add(id);
    });
  }

  void _onNavChanged() {
    // If the current destination was removed, fall back to the first item.
    if (!navController.value.contains(_currentId)) {
      setState(() => _currentId = navController.value.first);
    } else {
      setState(() {});
    }
  }

  /// Builds the screen for a destination id. Heavy screens (reels) are only
  /// built while selected; others are built lazily on first visit and kept.
  Widget _screenFor(String id) {
    switch (id) {
      case 'feed':
        return const FeedScreen();
      case 'reels':
        // Only mount while selected so its video doesn't play in the
        // background behind other tabs.
        return _currentId == 'reels'
            ? const ReelsScreen()
            : const SizedBox.shrink();
      case 'messages':
        return const MessagesScreen();
      case 'market':
        return const MarketplaceScreen();
      case 'profile':
        return MyProfileScreen(onSignedOut: widget.onSignedOut);
      case 'map':
        return const MapScreen();
      case 'communities':
        return const CommunitiesScreen();
      case 'groups':
        return const GroupsScreen();
      case 'wallet':
        return const WalletScreen();
      case 'search':
        return const SearchScreen();
      case 'notifications':
        return const NotificationsScreen();
      case 'guides':
        return const GuidesScreen();
      default:
        return const FeedScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = navController.value;
    final index = ids.indexOf(_currentId).clamp(0, ids.length - 1);
    return Scaffold(
      // Let the body show behind the floating nav pill instead of a dark strip.
      extendBody: true,
      body: IndexedStack(
        index: index,
        children: [
          for (final id in ids)
            // Lazy: build only visited destinations (and reels only when active).
            (_visited.contains(id) || id == _currentId)
                ? _screenFor(id)
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: OkayBottomNav(currentId: _currentId),
    );
  }
}
