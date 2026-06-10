import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../okayspace_api.dart';

/// A single API instance shared across the demo app.
final OkaySpaceApi api = OkaySpaceApi();

/// Bumped when the user taps the Feed tab while already on it — the feed
/// listens and scrolls to top + refreshes.
final ValueNotifier<int> feedScrollSignal = ValueNotifier<int>(0);

/// Animated progress of the top & bottom bars: 1.0 = fully shown, 0.0 = fully
/// hidden. The root app animates this toward [barsVisible]; [OkayAppBar] and
/// [OkayBottomNav] listen and collapse their reserved space accordingly, so the
/// body reclaims the room as they slide away.
final ValueNotifier<double> barsT = ValueNotifier<double>(1.0);

/// Target visibility of the bars. Scrolling down requests hide; scrolling up,
/// reaching the top, or navigating requests show.
final ValueNotifier<bool> barsVisible = ValueNotifier<bool>(true);

/// Reports a scroll gesture so the bars can hide/show. Only vertical scrolls
/// count — horizontal carousels (stories, tab swipes) never toggle the bars.
void reportUserScroll(ScrollDirection direction, Axis axis) {
  if (axis != Axis.vertical) return;
  if (direction == ScrollDirection.reverse) {
    barsVisible.value = false;
  } else if (direction == ScrollDirection.forward) {
    barsVisible.value = true;
  }
}

/// Forces the bars back into view (on navigation, tab switch, or reaching top).
void showBars() => barsVisible.value = true;

/// Bottom inset for scrollable content so the last item clears the floating
/// nav pill (which overlays the body via `extendBody`).
const double kBottomNavInset = 96;

/// Key to the home shell's [Scaffold] so any home-tab screen (each of which is
/// its own inner Scaffold) can open the shared navigation drawer (sidebar).
final GlobalKey<ScaffoldState> homeScaffoldKey = GlobalKey<ScaffoldState>();

/// Route name tagged on top-level destinations opened from the sidebar, so
/// their app bar shows the sidebar menu instead of a back button. Deeper
/// screens (pushed without this name) keep the back button.
const String kPrimaryRouteName = 'okay.primary';

/// Builds the sidebar widget for the modal fallback. Registered by the app so
/// this file doesn't need to import the drawer (which imports back here).
WidgetBuilder? sidebarModalBuilder;

/// Opens the navigation sidebar from anywhere:
/// - the screen's own drawer if it has one (feed, profile, home tabs),
/// - else, on a pushed route, a left slide-in modal (the home-shell drawer
///   would be hidden behind the current route),
/// - else the shared home-shell drawer.
void openSidebar(BuildContext context) {
  final local = Scaffold.maybeOf(context);
  if (local != null && local.hasDrawer) {
    local.openDrawer();
    return;
  }
  if (Navigator.of(context).canPop() && sidebarModalBuilder != null) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Menu',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.centerLeft,
        child: sidebarModalBuilder!(ctx),
      ),
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    );
    return;
  }
  homeScaffoldKey.currentState?.openDrawer();
}

/// A short display title for a conversation (group name, other user, members).
String conversationTitle(ConversationView c) {
  if (c.name != null && c.name!.isNotEmpty) return c.name!;
  if (c.otherUser != null) return c.otherUser!.name;
  if (c.members.isNotEmpty) return c.members.map((m) => m.name).join(', ');
  return 'Conversation';
}

/// Shows a sheet to pick one of the user's conversations (for sharing).
/// Returns the chosen conversation, or null if dismissed.
Future<ConversationView?> pickConversation(BuildContext context) async {
  final convs = await api.messaging
      .conversations()
      .catchError((_) => <ConversationView>[]);
  if (!context.mounted) return null;
  return showModalBottomSheet<ConversationView>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
              title: Text('Share to',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in convs)
                  ListTile(
                    leading: Avatar(
                        url: c.avatar ?? c.otherUser?.picture,
                        name: conversationTitle(c)),
                    title: Text(conversationTitle(c),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The home destination the shell should show, identified by its id (see
/// [kAllNavDests]). [OkayBottomNav] sets this from any screen; the shell
/// listens and switches tabs (popping back to it first).
class HomeTabSignal extends ValueNotifier<String> {
  HomeTabSignal(super.value);

  /// Selects [id], re-notifying even if it's already selected (so re-tapping
  /// the active tab still triggers listeners, e.g. feed scroll-to-top).
  void select(String id) {
    if (value == id) {
      notifyListeners();
    } else {
      value = id;
    }
  }
}

final HomeTabSignal homeTabSignal = HomeTabSignal('feed');

/// A navigation destination available for the customizable bottom bar.
class NavDest {
  const NavDest(this.id, this.label, this.icon, this.activeIcon);
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Every destination the user can place in the bottom navigation bar.
const List<NavDest> kAllNavDests = [
  NavDest('feed', 'Feed', Icons.home_outlined, Icons.home),
  NavDest('reels', 'Reels', Icons.play_circle_outline, Icons.play_circle),
  NavDest('messages', 'Messages', Icons.chat_bubble_outline, Icons.chat_bubble),
  NavDest('market', 'Market', Icons.storefront_outlined, Icons.storefront),
  NavDest('profile', 'Profile', Icons.person_outline, Icons.person),
  NavDest('map', 'Map', Icons.map_outlined, Icons.map),
  NavDest('communities', 'Communities', Icons.tag, Icons.tag),
  NavDest('groups', 'Groups', Icons.groups_outlined, Icons.groups),
  NavDest('wallet', 'Wallet', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet),
  NavDest('search', 'Search', Icons.search, Icons.search),
  NavDest('notifications', 'Alerts', Icons.notifications_outlined,
      Icons.notifications),
  NavDest('guides', 'Places', Icons.place_outlined, Icons.place),
];

NavDest navDestById(String id) =>
    kAllNavDests.firstWhere((d) => d.id == id, orElse: () => kAllNavDests.first);

/// The user's chosen bottom-nav destinations (ordered ids, max 5), persisted.
class NavController extends ValueNotifier<List<String>> {
  NavController() : super(const ['feed', 'reels', 'messages', 'market', 'profile']) {
    _load();
  }

  static const _key = 'okayspace.nav_items';
  static const int maxItems = 5;
  static const int minItems = 2;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null && stored.isNotEmpty) {
        final ids = stored
            .split(',')
            .where((id) => kAllNavDests.any((d) => d.id == id))
            .toList();
        if (ids.length >= minItems) value = ids.take(maxItems).toList();
      }
    } catch (_) {/* keep default */}
  }

  Future<void> set(List<String> ids) async {
    final clean = ids.take(maxItems).toList();
    if (clean.length < minItems) return;
    value = clean;
    try {
      await _storage.write(key: _key, value: clean.join(','));
    } catch (_) {/* best effort */}
  }

  /// Feed stays pinned so the sidebar (and nav customizer) is always reachable.
  static const String pinned = 'feed';

  bool get isFull => value.length >= maxItems;
  void add(String id) {
    if (isFull || value.contains(id)) return;
    set([...value, id]);
  }

  void remove(String id) {
    if (id == pinned || value.length <= minItems) return;
    set(value.where((e) => e != id).toList());
  }
}

final NavController navController = NavController();

/// A destination available in the customizable sidebar (drawer).
class SidebarDest {
  const SidebarDest(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

/// Destinations the user can place in the sidebar, in default order.
/// (Services and account shortcuts live under Settings instead.)
const List<SidebarDest> kAllSidebarDests = [
  SidebarDest('feed', 'Feed', Icons.home_rounded, Color(0xFF3B82F6)),
  SidebarDest('reels', 'Reels', Icons.videocam_rounded, Color(0xFFEC4899)),
  SidebarDest('map', 'Map', Icons.map_rounded, Color(0xFF10B981)),
  SidebarDest('marketplace', 'Marketplace', Icons.storefront_rounded,
      Color(0xFFF97316)),
  SidebarDest('communities', 'Communities', Icons.tag_rounded,
      Color(0xFF06B6D4)),
  SidebarDest('groups', 'Groups', Icons.groups_rounded, Color(0xFFA855F7)),
  SidebarDest('profile', 'My profile', Icons.person_rounded, Color(0xFF14B8A6)),
  SidebarDest('wallet', 'Wallet', Icons.account_balance_wallet_rounded,
      Color(0xFF22C55E)),
];

SidebarDest sidebarDestById(String id) => kAllSidebarDests.firstWhere(
    (d) => d.id == id,
    orElse: () => kAllSidebarDests.first);

/// The user's chosen sidebar destinations (ordered ids), persisted.
class SidebarController extends ValueNotifier<List<String>> {
  SidebarController()
      : super(const ['feed', 'map', 'marketplace', 'communities', 'groups']) {
    _load();
  }

  static const _key = 'okayspace.sidebar_items';
  static const int minItems = 1;
  static const int maxItems = 5;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null && stored.isNotEmpty) {
        final ids = stored
            .split(',')
            .where((id) => kAllSidebarDests.any((d) => d.id == id))
            .take(maxItems)
            .toList();
        if (ids.length >= minItems) value = ids;
      }
    } catch (_) {/* keep default */}
  }

  Future<void> set(List<String> ids) async {
    final clean = ids.take(maxItems).toList();
    if (clean.length < minItems) return;
    value = clean;
    try {
      await _storage.write(key: _key, value: clean.join(','));
    } catch (_) {/* best effort */}
  }

  bool get isFull => value.length >= maxItems;

  void add(String id) {
    if (isFull || value.contains(id)) return;
    set([...value, id]);
  }

  void remove(String id) {
    if (value.length <= minItems) return;
    set(value.where((e) => e != id).toList());
  }
}

final SidebarController sidebarController = SidebarController();

/// Whether the stories row is hidden on the feed. Persisted locally.
class HideStoriesController extends ValueNotifier<bool> {
  HideStoriesController() : super(false) {
    _load();
  }

  static const _key = 'okayspace.hide_stories';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> _load() async {
    try {
      value = (await _storage.read(key: _key)) == '1';
    } catch (_) {/* keep default */}
  }

  Future<void> set(bool hidden) async {
    value = hidden;
    try {
      await _storage.write(key: _key, value: hidden ? '1' : '0');
    } catch (_) {/* best effort */}
  }
}

final HideStoriesController hideStoriesController = HideStoriesController();

/// The floating, customizable pill bottom navigation shown on every screen.
/// Tapping an item returns to the home shell and selects that destination.
class OkayBottomNav extends StatelessWidget {
  const OkayBottomNav({super.key, this.currentId});

  /// Highlighted destination id when this screen *is* a home tab.
  final String? currentId;

  void _go(BuildContext context, String id) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (id == 'feed' && homeTabSignal.value == 'feed') {
      feedScrollSignal.value++;
    }
    homeTabSignal.select(id); // re-fires even if unchanged
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nav = ValueListenableBuilder<List<String>>(
      valueListenable: navController,
      builder: (context, ids, _) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
              for (final id in ids)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _go(context, id),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: id == currentId
                            ? scheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        id == currentId
                            ? navDestById(id).activeIcon
                            : navDestById(id).icon,
                        color: id == currentId ? Colors.white : scheme.outline,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Collapse downward as the bars hide: the slot shrinks to the measured
    // height, so the Scaffold body extends down to reclaim the space.
    return ValueListenableBuilder<double>(
      valueListenable: barsT,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t.clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: nav,
    );
  }
}

/// The signed-in user's id, cached after sign-in so widgets can tell which
/// content is the current user's (e.g. own-post actions). Null until loaded.
String? currentUserId;

/// Fetches and caches [currentUserId] from /auth/me (best effort).
Future<void> loadCurrentUserId() async {
  try {
    currentUserId = (await api.auth.me()).userId;
  } catch (_) {/* ignore */}
}

/// Exact design tokens pulled from the okayspace.ca web app (WhatsApp-style
/// dark theme with a teal accent).
abstract final class OkayColors {
  static const bg = Color(0xFF0B141A);
  static const surface = Color(0xFF1F2C33);
  static const surfaceAlt = Color(0xFF2A3942);
  static const primary = Color(0xFF00A884);
  static const primaryHover = Color(0xFF06CF9C);
  static const primaryActive = Color(0xFF008F6F);
  static const bubbleOut = Color(0xFF005C4B); // outgoing chat bubble
  static const textPrimary = Color(0xFFE9EDEF);
  static const textSecondary = Color(0xFFAEBAC1);
  static const textMuted = Color(0xFF8696A0);
  static const border = Color(0x2E8696A0); // rgba(134,150,160,0.18)
  static const danger = Color(0xFFEF4444);
  static const warning = Color(0xFFF6C455);
}

/// App-wide theme mode (system/light/dark), persisted across launches.
final ThemeController themeController = ThemeController();

/// App-wide accent color, persisted across launches.
final AccentController accentController = AccentController();

/// A selectable accent, mirroring okayspace.ca's accent themes.
class AccentOption {
  const AccentOption(this.label, this.color);
  final String label;
  final Color color;
}

/// The accent palette from okayspace.ca.
const List<AccentOption> kAccents = [
  AccentOption('Default', OkayColors.primary), // teal #00A884
  AccentOption('Emerald', Color(0xFF10B981)),
  AccentOption('Ocean', Color(0xFF06B6D4)),
  AccentOption('Carbon', Color(0xFFA1A1AA)),
  AccentOption('Nebula', Color(0xFFA855F7)),
  AccentOption('Sunset', Color(0xFFF97316)),
  AccentOption('Midnight', Color(0xFF6366F1)),
  AccentOption('Rosé', Color(0xFFF43F5E)),
];

/// Holds the selected accent [Color] and persists it to secure storage.
class AccentController extends ValueNotifier<Color> {
  AccentController() : super(OkayColors.primary) {
    _load();
  }

  static const _key = 'okayspace.accent';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: _key);
      final argb = stored == null ? null : int.tryParse(stored);
      if (argb != null) value = Color(argb);
    } catch (_) {/* keep default */}
  }

  Future<void> set(Color color) async {
    value = color;
    try {
      await _storage.write(key: _key, value: color.toARGB32().toString());
    } catch (_) {/* best effort */}
  }
}

/// Returns a darkened shade of [color] (used for pressed/container tints and
/// outgoing chat bubbles).
Color darken(Color color, [double amount = 0.12]) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

/// Holds the selected [ThemeMode] and persists it to secure storage.
class ThemeController extends ValueNotifier<ThemeMode> {
  // OkaySpace's web app is dark-only, so we default to dark to match it.
  ThemeController() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'okayspace.theme_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> _load() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null) {
        value = ThemeMode.values.firstWhere(
          (m) => m.name == stored,
          orElse: () => ThemeMode.system,
        );
      }
    } catch (_) {/* fall back to system */}
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {/* best effort */}
  }
}

/// Extracts a user-facing message from any error thrown by the client.
String messageFor(Object? error) =>
    error is ApiException ? error.message : '${error ?? 'Something went wrong.'}';

/// Shows a transient error message as a floating snackbar.
void showError(BuildContext context, Object? error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(messageFor(error)),
    behavior: SnackBarBehavior.floating,
  ));
}

/// Shows a brief confirmation snackbar.
void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
  ));
}

/// Centers and constrains [child] to [maxWidth] on large screens (web/tablet).
/// On phones (narrower than [maxWidth]) it has no visible effect.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.maxWidth = 680});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Prompts for a single block of text in a dialog. Returns null if cancelled
/// or empty.
Future<String?> promptText(BuildContext context,
    {required String title,
    String hint = '',
    String action = 'Post',
    String? initial}) async {
  final controller = TextEditingController(text: initial);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration:
              InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(action)),
        ],
      ),
    );
    final text = result?.trim();
    return (text == null || text.isEmpty) ? null : text;
  } finally {
    controller.dispose();
  }
}

/// Compact count formatter: 1200 → "1.2k", 3_400_000 → "3.4M".
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v < 10 && n % 1000 >= 100 ? 1 : 0)}k';
  }
  final v = n / 1000000;
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)}M';
}

/// Compact relative-time formatter (e.g. "3m", "2h", "5d").
String shortAgo(DateTime time) {
  final d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

/// A circular avatar that falls back to a colored initial.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, this.name, this.radius = 20});

  final String? url;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasName = name != null && name!.isNotEmpty;
    final initial = hasName ? name![0].toUpperCase() : '?';
    // Deterministic tint per name so avatars are distinguishable.
    final hue = hasName ? (name!.codeUnitAt(0) * 47) % 360 : 200;
    final bg = HSLColor.fromAHSL(1, hue.toDouble(), 0.5, 0.6).toColor();
    final hasImage = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: hasImage ? NetworkImage(url!) : null,
      // Swallow image load errors (broken URLs) so they don't spam the
      // console; the colored circle remains as the fallback.
      onBackgroundImageError: hasImage ? (_, __) {} : null,
      child: hasImage
          ? null
          : Text(initial,
              style: TextStyle(
                  fontSize: radius * 0.8,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
    );
  }
}

/// App-wide header styled like the newsfeed: a rounded "pill" surface card
/// with a leading icon (back/menu), a bold title, and trailing actions —
/// a drop-in replacement for [AppBar] in `Scaffold.appBar`.
class OkayAppBar extends StatelessWidget implements PreferredSizeWidget {
  const OkayAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.automaticallyImplyLeading = true,
    // Accepted for drop-in compatibility with AppBar; styling is fixed.
    this.titleSpacing,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.scrolledUnderElevation,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final double? titleSpacing;
  final bool? centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final double? scrolledUnderElevation;

  static const double _row = 56;

  @override
  Size get preferredSize => Size.fromHeight(
      // 12 vertical margin + 56 row + 4 slack, plus the bottom widget's
      // height and its 6px gap when present.
      72 + (bottom == null ? 0 : bottom!.preferredSize.height + 8));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Top-level destinations (home tabs + screens opened from the sidebar)
    // show the sidebar menu; deeper pushed screens show a back button. Screens
    // that pass an explicit [leading] (e.g. Settings sub-pages) keep it.
    final route = ModalRoute.of(context);
    final isPrimary = route == null ||
        route.isFirst ||
        route.settings.name == kPrimaryRouteName;
    final canPop = automaticallyImplyLeading && Navigator.canPop(context);
    final Widget? lead = leading ??
        (!automaticallyImplyLeading
            ? null
            : (isPrimary || !canPop)
                ? IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'Menu',
                    onPressed: () => openSidebar(context),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                  ));

    final bar = SafeArea(
      bottom: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _row,
              child: Row(
                children: [
                  if (lead != null)
                    lead
                  else
                    const SizedBox(width: 16),
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, fontSize: 21),
                      overflow: TextOverflow.ellipsis,
                      child: title ?? const SizedBox.shrink(),
                    ),
                  ),
                  if (actions != null) ...actions!,
                  if (actions == null || actions!.isEmpty)
                    const SizedBox(width: 8),
                ],
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: bottom!,
              ),
          ],
        ),
      ),
    );

    // Collapse upward as the bars hide: the slot shrinks to the measured
    // height, so the Scaffold body slides up to reclaim the space.
    return ValueListenableBuilder<double>(
      valueListenable: barsT,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: t.clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: bar,
    );
  }
}

/// A friendly empty/error state with an icon, message and optional retry.
/// Lives in a scrollable so it works inside [RefreshIndicator].
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({
    super.key,
    required this.message,
    this.icon,
    this.onRetry,
  });

  final String message;
  final IconData? icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.outline;
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: constraints.maxHeight * 0.20),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon ?? Icons.inbox_outlined,
                  size: 40, color: scheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: muted, fontSize: 14.5, height: 1.35)),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A softly-pulsing placeholder box used to build loading skeletons.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_c),
      child: Container(
        width: widget.shape == BoxShape.circle ? widget.height : widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.rectangle
              ? BorderRadius.circular(widget.radius)
              : null,
        ),
      ),
    );
  }
}

/// A list of skeleton "post" rows shown while a feed loads.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(height: 40, shape: BoxShape.circle),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 120, height: 12),
                  SizedBox(height: 8),
                  Skeleton(height: 12),
                  SizedBox(height: 6),
                  Skeleton(width: 200, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list of skeleton rows (avatar + two lines) for loading list screens.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Skeleton(height: 44, shape: BoxShape.circle),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 140, height: 12),
                  SizedBox(height: 8),
                  Skeleton(width: 220, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A grid of skeleton tiles for loading grid screens (e.g. marketplace).
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.tiles = 6});

  final int tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: tiles,
      itemBuilder: (_, __) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Skeleton(height: double.infinity, radius: 14)),
          SizedBox(height: 6),
          Skeleton(width: 120, height: 12),
          SizedBox(height: 6),
          Skeleton(width: 70, height: 10),
        ],
      ),
    );
  }
}

/// Standard async-list scaffold: a [loading] placeholder while loading, an
/// error+retry state on failure, an [emptyMessage] when empty, else [builder].
class AsyncList<T> extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.future,
    required this.builder,
    this.emptyMessage = 'Nothing here yet.',
    this.emptyIcon,
    this.loading,
  });

  final Future<List<T>> future;
  final Widget Function(BuildContext, List<T>) builder;
  final String emptyMessage;
  final IconData? emptyIcon;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // A skeleton reads as more polished than a bare spinner; callers can
          // still pass a tailored one (e.g. GridSkeleton/FeedSkeleton).
          return loading ?? const ListSkeleton();
        }
        if (snapshot.hasError) {
          return CenteredMessage(
              message: messageFor(snapshot.error),
              icon: Icons.error_outline);
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return CenteredMessage(message: emptyMessage, icon: emptyIcon);
        }
        return builder(context, items);
      },
    );
  }
}
