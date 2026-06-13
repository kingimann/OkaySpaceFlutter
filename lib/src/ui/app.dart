import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update_checker.dart';
import 'app_drawer.dart';
import 'common.dart';
import 'home_shell.dart';
import 'register_screen.dart';

/// Root widget for the OkaySpace demo app.
class OkaySpaceApp extends StatefulWidget {
  const OkaySpaceApp({super.key});

  @override
  State<OkaySpaceApp> createState() => _OkaySpaceAppState();
}

class _OkaySpaceAppState extends State<OkaySpaceApp>
    with SingleTickerProviderStateMixin {
  final _navKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _barsNavObserver = _BarsNavObserver();
  bool _resetting = false;

  // Drives the top/bottom bar hide-on-scroll animation (1 = shown, 0 = hidden).
  late final AnimationController _bars = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1.0,
  )..addListener(() => barsT.value = _bars.value);

  @override
  void initState() {
    super.initState();
    // Lets openSidebar() present the drawer as a modal on pushed routes.
    sidebarModalBuilder = (_) => const AppDrawer();
    // Animate the bars whenever the requested visibility changes, and snap them
    // back into view whenever the user switches home tabs.
    barsVisible.addListener(_animateBars);
    homeTabSignal.addListener(showBars);
    // Show a banner when a newer build is deployed while the app is open.
    updateAvailable.addListener(_onUpdateAvailable);
    mobileWebGate.addListener(_onMobileGate);
    startUpdateChecks();
    // When the server rejects our credential, drop back to the gate (login).
    api.client.onUnauthorized = () {
      if (_resetting) return;
      _resetting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resetting = false;
        _navKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RootGate()),
          (route) => false,
        );
      });
    };
  }

  void _animateBars() => barsVisible.value ? _bars.forward() : _bars.reverse();

  void _onUpdateAvailable() {
    if (!updateAvailable.value) return;
    _messengerKey.currentState
      ?..hideCurrentMaterialBanner()
      ..showMaterialBanner(MaterialBanner(
        content: const Text('A new version of OkaySpace is available.'),
        leading: const Icon(Icons.system_update_alt),
        actions: [
          TextButton(
            onPressed: () =>
                _messengerKey.currentState?.hideCurrentMaterialBanner(),
            child: const Text('Later'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: reloadApp,
            child: const Text('Reload'),
          ),
        ],
      ));
  }

  // Store links for the mobile-web gate, set at build time once the native
  // apps are published. With neither configured the gate is inert, so
  // phone-browser testing keeps working.
  static const _appStoreUrl = String.fromEnvironment('APP_STORE_URL');
  static const _playStoreUrl = String.fromEnvironment('PLAY_STORE_URL');
  bool _gateShown = false;

  void _onMobileGate() {
    if (!mobileWebGate.value || _gateShown || !kIsWeb) return;
    if (_appStoreUrl.isEmpty && _playStoreUrl.isEmpty) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    if (shortest >= 600) return; // tablets/desktops aren't gated
    _gateShown = true; // once per session — dismissible, never a wall
    _messengerKey.currentState?.showMaterialBanner(MaterialBanner(
      content: const Text('OkaySpace is better in the app.'),
      leading: const Icon(Icons.smartphone),
      actions: [
        TextButton(
          onPressed: () =>
              _messengerKey.currentState?.hideCurrentMaterialBanner(),
          child: const Text('Continue in browser'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => launchUrl(
            Uri.parse(_appStoreUrl.isNotEmpty ? _appStoreUrl : _playStoreUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Get the app'),
        ),
      ],
    ));
  }

  @override
  void dispose() {
    barsVisible.removeListener(_animateBars);
    homeTabSignal.removeListener(showBars);
    updateAvailable.removeListener(_onUpdateAvailable);
    mobileWebGate.removeListener(_onMobileGate);
    _bars.dispose();
    super.dispose();
  }

  /// The okayspace.ca dark color scheme, mapped role-for-role.
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: OkayColors.primary,
    onPrimary: Colors.white,
    primaryContainer: OkayColors.primaryActive,
    onPrimaryContainer: Colors.white,
    secondary: OkayColors.primary,
    onSecondary: Colors.white,
    surface: OkayColors.bg,
    onSurface: OkayColors.textPrimary,
    surfaceContainerLowest: OkayColors.bg,
    surfaceContainerLow: OkayColors.surface,
    surfaceContainer: OkayColors.surface,
    surfaceContainerHigh: OkayColors.surfaceAlt,
    surfaceContainerHighest: OkayColors.surfaceAlt,
    onSurfaceVariant: OkayColors.textSecondary,
    outline: OkayColors.textMuted,
    outlineVariant: OkayColors.border,
    error: OkayColors.danger,
    onError: Colors.white,
  );

  /// A light counterpart (okayspace is dark-only; this keeps the toggle usable)
  /// using the same teal accent.
  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: OkayColors.primary,
    brightness: Brightness.light,
  );

  ThemeData _theme(Brightness brightness, Color accent) {
    final base = brightness == Brightness.dark ? _darkScheme : _lightScheme;
    final scheme = base.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      primaryContainer: darken(accent),
      onPrimaryContainer: Colors.white,
    );
    final headerColor =
        brightness == Brightness.dark ? OkayColors.surface : scheme.surface;
    // Force every text style to use the scheme's onSurface color. Without this,
    // some inherited/default styles can fall back to black, which is unreadable
    // on the dark theme.
    final baseText = ThemeData(brightness: brightness, useMaterial3: true)
        .textTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          decorationColor: scheme.onSurface,
        );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      textTheme: baseText,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: headerColor,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: headerColor,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: OkayColors.border,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark
            ? OkayColors.surfaceAlt
            : scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: scheme.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      // On-brand spinners everywhere.
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide.none,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface),
        subtitleTextStyle: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        iconColor: scheme.onSurfaceVariant,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: accent,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.outline,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        actionTextColor: accent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) => ValueListenableBuilder<Color>(
        valueListenable: accentController,
        builder: (context, accent, _) => MaterialApp(
          title: 'OkaySpace',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navKey,
          scaffoldMessengerKey: _messengerKey,
          navigatorObservers: [_barsNavObserver],
          theme: _theme(Brightness.light, accent),
          darkTheme: _theme(Brightness.dark, accent),
          themeMode: mode,
          // App-wide hide-on-scroll: any vertical scroll hides the bars;
          // scrolling back up or reaching the top reveals them again.
          builder: (context, child) => NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis != Axis.vertical) return false;
              if (n is UserScrollNotification) {
                // Content that can't actually scroll (short/empty screens, or
                // a bounce overscroll) must never hide the bars.
                if (n.metrics.maxScrollExtent <= 0) {
                  showBars();
                } else {
                  reportUserScroll(n.direction, n.metrics.axis);
                }
              } else if (n is ScrollUpdateNotification &&
                  n.metrics.pixels <= n.metrics.minScrollExtent + 8) {
                showBars();
              }
              return false;
            },
            child: child!,
          ),
          home: const RootGate(),
        ),
      ),
    );
  }
}

/// Re-shows the top/bottom bars whenever a route is pushed or popped, so a new
/// screen never opens with its bars hidden from the previous screen's scroll.
class _BarsNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      showBars();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      showBars();
}

/// Shows the app shell when signed in, otherwise the login screen.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late Future<bool> _authed;

  @override
  void initState() {
    super.initState();
    _authed = api.isAuthenticated;
  }

  void _refresh() => setState(() => _authed = api.isAuthenticated);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authed,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _SplashScreen();
        }
        return snapshot.data!
            ? HomeShell(onSignedOut: _refresh)
            : LoginScreen(onSignedIn: _refresh);
      },
    );
  }
}

/// Branded loading screen shown while the stored session is checked.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, darken(scheme.primary, 0.18)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.public, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text('OkaySpace',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Email/username/phone + password login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await api.auth.login(
        identifier: _identifier.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      if (result.hasToken) {
        widget.onSignedIn();
      } else {
        setState(() => _error = 'Additional verification required.');
      }
    } catch (e) {
      setState(() => _error = messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        darken(Theme.of(context).colorScheme.primary, 0.18),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.public, size: 44, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text('OkaySpace',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Welcome back',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 32),
              TextField(
                controller: _identifier,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email, username or phone',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              RegisterScreen(onSignedIn: widget.onSignedIn),
                        )),
                child: const Text("Don't have an account? Create one"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
