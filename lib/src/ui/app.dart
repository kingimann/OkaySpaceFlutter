import 'package:flutter/material.dart';

import 'common.dart';
import 'home_shell.dart';
import 'register_screen.dart';

/// Root widget for the OkaySpace demo app.
class OkaySpaceApp extends StatelessWidget {
  const OkaySpaceApp({super.key});

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
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
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
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
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
          theme: _theme(Brightness.light, accent),
          darkTheme: _theme(Brightness.dark, accent),
          themeMode: mode,
          home: const RootGate(),
        ),
      ),
    );
  }
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data!
            ? HomeShell(onSignedOut: _refresh)
            : LoginScreen(onSignedIn: _refresh);
      },
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
              Icon(Icons.public,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text('OkaySpace',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 32),
              TextField(
                controller: _identifier,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Email, username or phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign in'),
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
