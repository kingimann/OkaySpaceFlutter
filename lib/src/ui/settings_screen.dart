import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'api_keys_screen.dart';
import 'app.dart';
import 'common.dart';

/// Account, privacy and notification settings, backed by the auth service.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.user});

  final User user;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _private = widget.user.isPrivate;
  // raw values may be true/false/null; searchable defaults on, others off.
  late bool _searchable = widget.user.raw['searchable'] != false;
  late bool _hideOnline = widget.user.raw['hide_online'] == true;
  late bool _sms = widget.user.raw['sms_notifications'] == true;

  /// Optimistically flips [current], persists [field]=value, reverts on error.
  Future<void> _toggle(
      String field, bool value, void Function(bool) apply) async {
    apply(value);
    setState(() {});
    try {
      await api.auth.updateProfile({field: value});
    } catch (e) {
      apply(!value);
      if (mounted) {
        setState(() {});
        showError(context, e);
      }
    }
  }

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (ok == true && mounted) showInfo(context, 'Password updated');
  }

  Future<void> _signOut() async {
    await api.auth.logout();
    if (!mounted) return;
    // Replace the stack with a fresh gate; it re-checks auth and shows login.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RootGate()),
      (route) => false,
    );
  }

  Future<void> _pickTheme() async {
    final current = themeController.value;
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('Appearance',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            for (final m in ThemeMode.values)
              ListTile(
                title: Text(switch (m) {
                  ThemeMode.system => 'System default',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                trailing: m == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (mode != null) themeController.set(mode);
  }

  String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  Future<void> _pickAccent() async {
    final chosen = await showModalBottomSheet<Color>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final a in kAccents)
                GestureDetector(
                  onTap: () => Navigator.pop(context, a.color),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: a.color,
                          shape: BoxShape.circle,
                          border: a.color.toARGB32() ==
                                  accentController.value.toARGB32()
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 3)
                              : null,
                        ),
                        child: a.color.toARGB32() ==
                                accentController.value.toARGB32()
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 20)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(a.label,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) accentController.set(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: MaxWidth(
        child: ListView(
        children: [
          _section('Account'),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Email'),
            subtitle: Text(widget.user.email),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePassword,
          ),
          const Divider(height: 1),
          _section('Display'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Appearance'),
            trailing: Text(_themeLabel(themeController.value)),
            onTap: () async {
              await _pickTheme();
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Accent color'),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            onTap: _pickAccent,
          ),
          const Divider(height: 1),
          _section('Privacy'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Private account'),
            subtitle: const Text('Only approved followers see your posts'),
            value: _private,
            onChanged: (v) =>
                _toggle('is_private', v, (x) => _private = x),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.search),
            title: const Text('Searchable'),
            subtitle: const Text('Let people find you in search'),
            value: _searchable,
            onChanged: (v) =>
                _toggle('searchable', v, (x) => _searchable = x),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide online status'),
            value: _hideOnline,
            onChanged: (v) =>
                _toggle('hide_online', v, (x) => _hideOnline = x),
          ),
          const Divider(height: 1),
          _section('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.sms_outlined),
            title: const Text('SMS notifications'),
            value: _sms,
            onChanged: (v) =>
                _toggle('sms_notifications', v, (x) => _sms = x),
          ),
          const Divider(height: 1),
          _section('Developer'),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('API keys'),
            subtitle: const Text('Generate keys for the OkaySpace API'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ApiKeysScreen(),
            )),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Sign out',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: _signOut,
          ),
        ],
      ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.isEmpty || _next.text.length < 6) return;
    setState(() => _busy = true);
    try {
      await api.auth.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Current password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'New password (min 6)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Update'),
        ),
      ],
    );
  }
}
