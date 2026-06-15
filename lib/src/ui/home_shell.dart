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
import 'right_sidebar.dart';
import 'videos_screen.dart';
import 'search_screen.dart';
import 'wallet_screen.dart';

/// The signed-in app shell: a persistent [Scaffold] whose bottom navigation bar
/// stays put on EVERY screen. Feature screens are pushed into a nested
/// [Navigator] in the body (below the bar), so the bar never disappears and is
/// never an overlay that could glitch or show a black backdrop.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Highlighted nav destination, kept in sync with the visible home tab.
  String _currentId = navController.value.first;

  // Banks foreground time as points (small, daily-capped) while signed in.
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    appSignedIn.value = true;
    loadCurrentUserId();
    refreshMarketplaceOffersBadge();
    homeTabSignal.addListener(_onTabSignal);
    navController.addListener(_onNavChanged);
    WidgetsBinding.instance.addObserver(this);
    pointsLedger.noteActive();
    _onlineTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => pointsLedger.accrue());
  }

  @override
  void dispose() {
    appSignedIn.value = false;
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
    // Selecting a destination returns to the home tabs: pop any pushed feature
    // screen off the nested navigator, then show the chosen tab.
    contentNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _currentId = id);
  }

  void _onNavChanged() {
    // If the current destination was removed from the bar, fall back to the
    // first item.
    if (!navController.value.contains(_currentId)) {
      setState(() => _currentId = navController.value.first);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: homeScaffoldKey,
      // Let the body paint behind the floating pill nav so content (not a bare
      // reserved strip) shows around it — no "black box" behind the pill. With
      // this on, the Scaffold also adds the bar's height to the body's bottom
      // MediaQuery padding, so SafeArea-based content clears the pill, and
      // kBottomNavInset covers the scroll lists that pad by a constant.
      extendBody: true,
      // Shared sidebar, reachable from every screen's menu button.
      drawer: const AppDrawer(),
      // Right-side quick-shortcuts sidebar: swipe from the right edge or tap the
      // top-right menu button (which replaced the scattered header icons).
      endDrawer: const RightSidebar(),
      // Scrolling the drawer can hide the bars; restore them when it closes.
      onDrawerChanged: (open) {
        if (!open) showBars();
      },
      // Feature screens push into this nested Navigator, which lives in the body
      // BELOW the bottom nav — so the bar shows on every screen with no overlay.
      // NavigatorPopHandler forwards the system back gesture to it.
      body: NavigatorPopHandler(
        onPopWithResult: (_) => contentNavigatorKey.currentState?.maybePop(),
        child: Navigator(
          key: contentNavigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute(
            settings: settings,
            builder: (_) => _HomeTabs(onSignedOut: widget.onSignedOut),
          ),
        ),
      ),
      // The one and only bottom nav: a real Scaffold bottomNavigationBar.
      // Hidden while the keyboard is up so it never sits on top of it.
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
          ? null
          : OkayBottomNav(currentId: _currentId),
    );
  }
}

/// The home tabs themselves — the first route in the shell's nested navigator.
/// Holds an [IndexedStack] of the user's chosen destinations and switches
/// between them in response to [homeTabSignal].
class _HomeTabs extends StatefulWidget {
  const _HomeTabs({required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<_HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<_HomeTabs> {
  late String _currentId = navController.value.first;
  final Set<String> _visited = {};

  @override
  void initState() {
    super.initState();
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
    return IndexedStack(
      index: index,
      children: [
        for (final id in ids)
          // Lazy: build only visited destinations (and reels only when active).
          (_visited.contains(id) || id == _currentId)
              ? _screenFor(id)
              : const SizedBox.shrink(),
      ],
    );
  }
}
