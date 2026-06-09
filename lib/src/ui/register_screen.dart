import 'dart:async';

import 'package:flutter/material.dart';

import 'common.dart';

/// Account creation. On success the session token is stored and [onSignedIn]
/// fires, dropping the user into the app.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  // Debounced username availability.
  Timer? _debounce;
  bool? _usernameAvailable;
  bool _checkingUsername = false;

  @override
  void initState() {
    super.initState();
    _username.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    _debounce?.cancel();
    final value = _username.text.trim();
    setState(() {
      _usernameAvailable = null;
      _checkingUsername = value.length >= 3;
    });
    if (value.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final available = await api.auth.isUsernameAvailable(value);
        if (mounted && _username.text.trim() == value) {
          setState(() {
            _usernameAvailable = available;
            _checkingUsername = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _checkingUsername = false);
      }
    });
  }

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await api.auth.register(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
        username: _username.text.trim(),
      );
      if (!mounted) return;
      if (result.hasToken) {
        widget.onSignedIn();
        // Pop back through the navigation stack to the gate.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        setState(() => _error = 'Check your email to verify your account.');
      }
    } catch (e) {
      setState(() => _error = messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget? _usernameSuffix() {
    if (_checkingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_usernameAvailable == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (_usernameAvailable == false) {
      return const Icon(Icons.cancel, color: Colors.red);
    }
    return null;
  }

  bool get _canSubmit =>
      !_busy &&
      _name.text.trim().isNotEmpty &&
      _username.text.trim().length >= 3 &&
      _email.text.contains('@') &&
      _password.text.length >= 6 &&
      _usernameAvailable != false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _username,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  border: const OutlineInputBorder(),
                  suffixIcon: _usernameSuffix(),
                  helperText: _usernameAvailable == false
                      ? 'That username is taken'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Password (min 6 characters)',
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
                onPressed: _canSubmit ? _register : null,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
