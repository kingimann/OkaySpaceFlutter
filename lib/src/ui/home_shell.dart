import 'dart:async';

import 'package:flutter/material.dart';

import '../core/points_ledger.dart';
import 'app_drawer.dart';
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
import 'videos_screen.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late String _currentId = navController.value.first;
  final Set<String> _visited = {};

  // Banks foreground time as points (small, daily-capped) while signed in.
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    loadCurrentUserId();
    refreshMarketplaceOffersBadge();
    _visited.add(_currentId);
    homeTabSignal.addListener(_onTabSignal);
    navController.addListener(_onNavChanged);
    // Start banking online-time points.
    WidgetsBinding.instance.addObserver(this);
    pointsLedger.noteActive();
    _onlineTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => pointsLedger.accrue());
  }

  @override
  void dispose() {
    homeTabSignal.removeListener(_onTabSignal);
    navController.removeListener(_onNavChanged);
    _onlineTimer?.cancel();
    pointsLedger.noteInactive();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      pointsLedger.noteActive();
    } else {
      // Bank whatever foreground time accrued, then pause counting.
      pointsLedger.noteInactive();
    }
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
            ? const ReelsScreen(embedded: true)
            : const SizedBox.shrink();
      case 'videos':
        return const VideosScreen(embedded: true);
      case 'messages':
        return const MessagesScreen();
      case 'market':
        return const MarketplaceScreen(embedded: true);
      case 'profile':
        return MyProfileScreen(onSignedOut: widget.onSignedOut);
      case 'map':
        return const MapScreen(embedded: true);
      case 'communities':
        return const CommunitiesScreen(embedded: true);
      case 'groups':
        return const GroupsScreen(embedded: true);
      case 'wallet':
        return const WalletScreen(embedded: true);
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
      key: homeScaffoldKey,
      // Shared sidebar, reachable from every home-tab screen's menu button.
      drawer: const AppDrawer(),
      // Scrolling the drawer can hide the bars; restore them when it closes.
      onDrawerChanged: (open) {
        if (!open) showBars();
      },
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
