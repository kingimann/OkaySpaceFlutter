import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../okayspace_api.dart';

/// A single API instance shared across the demo app.
final OkaySpaceApi api = OkaySpaceApi();

/// Bumped when the user taps the Feed tab while already on it — the feed
/// listens and scrolls to top + refreshes.
final ValueNotifier<int> feedScrollSignal = ValueNotifier<int>(0);

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
  final result = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(action)),
      ],
    ),
  );
  final text = result?.trim();
  return (text == null || text.isEmpty) ? null : text;
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
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: (url == null || url!.isEmpty)
          ? Text(initial,
              style: TextStyle(
                  fontSize: radius * 0.8,
                  color: Colors.white,
                  fontWeight: FontWeight.w600))
          : null,
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
  Size get preferredSize =>
      Size.fromHeight(_row + 16 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = automaticallyImplyLeading && Navigator.canPop(context);
    final Widget? lead = leading ??
        (canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              )
            : null);

    return SafeArea(
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
    final muted = Theme.of(context).colorScheme.outline;
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        children: [
          SizedBox(height: constraints.maxHeight * 0.22),
          Icon(icon ?? Icons.inbox_outlined, size: 56, color: muted),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted)),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
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
          return loading ?? const Center(child: CircularProgressIndicator());
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
