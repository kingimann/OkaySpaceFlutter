import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'ads_screen.dart';
import 'api_keys_screen.dart';
import 'app.dart';
import 'bookmarks_screen.dart';
import 'circles_screen.dart';
import 'common.dart';
import 'connections_screen.dart';
import 'customize_nav_screen.dart';
import 'customize_sidebar_screen.dart';
import 'forms_screen.dart';
import 'friends_screen.dart';
import 'guides_screen.dart';
import 'connected_apps_screen.dart';
import 'documents_screen.dart';
import 'games_screen.dart';
import 'leaderboard_screen.dart';
import 'monetize_screen.dart';
import 'muted_words_screen.dart';
import 'roadside_screen.dart';
import 'support_screen.dart';

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
  late bool _hideLikes = widget.user.raw['hide_likes'] == true;
  late bool _showPoints = widget.user.raw['show_points'] != false;
  late String _messagePolicy =
      '${widget.user.raw['message_policy'] ?? 'everyone'}';
  late String _tagPolicy = '${widget.user.raw['tag_policy'] ?? 'everyone'}';
  late String _commentPolicy =
      '${widget.user.raw['default_comment_policy'] ?? 'everyone'}';
  late String _connectionsVisibility =
      '${widget.user.raw['connections_visibility'] ?? 'everyone'}';
  late final List<String> _muted = [
    for (final k in (widget.user.raw['muted_keywords'] as List? ?? const []))
      '$k'
  ];

  static const _policyLabels = {
    'everyone': 'Everyone',
    'followers': 'Followers',
    'none': 'No one',
  };

  /// Bottom-sheet picker for an everyone/followers/none policy field.
  Future<void> _pickPolicy(
      String title, String field, String current, void Function(String) apply) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            for (final e in _policyLabels.entries)
              ListTile(
                title: Text(e.value),
                trailing: e.key == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen == current) return;
    apply(chosen);
    setState(() {});
    try {
      await api.auth.updateProfile({field: chosen});
    } catch (e) {
      apply(current);
      if (mounted) {
        setState(() {});
        showError(context, e);
      }
    }
  }

  Future<void> _editMuted() async {
    final tag = await promptText(context,
        title: 'Mute a keyword',
        hint: 'Posts containing it are hidden',
        action: 'Mute');
    if (tag == null) return;
    final clean = tag.trim().toLowerCase();
    if (clean.isEmpty || _muted.contains(clean)) return;
    setState(() => _muted.add(clean));
    try {
      await api.auth.updateProfile({'muted_keywords': _muted});
    } catch (e) {
      setState(() => _muted.remove(clean));
      if (mounted) showError(context, e);
    }
  }

  Future<void> _unmute(String tag) async {
    setState(() => _muted.remove(tag));
    try {
      await api.auth.updateProfile({'muted_keywords': _muted});
    } catch (e) {
      setState(() => _muted.add(tag));
      if (mounted) showError(context, e);
    }
  }

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

  late bool _twofa = widget.user.twofaEnabled;

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (ok == true && mounted) showInfo(context, 'Password updated');
  }

  Future<void> _changeUsername() async {
    final username = await promptText(context,
        title: 'Change username',
        hint: 'new_username',
        action: 'Save',
        initial: widget.user.username);
    if (username == null) return;
    try {
      await api.auth.changeUsername(username.replaceFirst('@', '').trim());
      if (mounted) showInfo(context, 'Username updated');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _changeEmail() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangeEmailDialog(),
    );
    if (ok == true && mounted) showInfo(context, 'Email updated');
  }

  Future<void> _verifyEmail() async {
    try {
      await api.auth.sendEmailCode();
      if (!mounted) return;
      final code = await promptText(context,
          title: 'Verify email',
          hint: 'Code sent to ${widget.user.email}',
          action: 'Verify');
      if (code == null) return;
      await api.auth.verifyEmail(code);
      if (mounted) showInfo(context, 'Email verified');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _managePhone() async {
    final phone = await promptText(context,
        title: 'Phone number',
        hint: '+1 555 123 4567',
        action: 'Send code',
        initial: widget.user.phone);
    if (phone == null) return;
    try {
      await api.auth.sendPhoneCode(phone.trim());
      if (!mounted) return;
      final code = await promptText(context,
          title: 'Verify phone', hint: 'SMS code', action: 'Verify');
      if (code == null) return;
      await api.auth.verifyPhone(code);
      if (mounted) showInfo(context, 'Phone verified');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggle2fa(bool enable) async {
    final password = await promptText(context,
        title: enable ? 'Enable 2FA' : 'Disable 2FA',
        hint: 'Confirm your password',
        action: enable ? 'Enable' : 'Disable');
    if (password == null) return;
    try {
      await api.auth.setTwoFactor(enabled: enable, password: password);
      if (mounted) {
        setState(() => _twofa = enable);
        showInfo(context, enable ? '2FA enabled' : '2FA disabled');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
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

  // Which sub-page is open; null shows the category hub.
  String? _page;

  static const _pageTitles = {
    'account': 'Account',
    'privacy': 'Privacy & safety',
    'notifications': 'Notifications',
    'appearance': 'Appearance',
    'navigation': 'Navigation',
    'shortcuts': 'Shortcuts & tools',
    'developer': 'Developer',
  };

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PopScope(
      // On a sub-page, the back gesture returns to the hub instead of leaving.
      canPop: page == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _page = null);
      },
      child: Scaffold(
        appBar: OkayAppBar(
          title: Text(page == null ? 'Settings' : _pageTitles[page] ?? 'Settings'),
          leading: page == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _page = null),
                ),
        ),
        body: MaxWidth(
          child: page == null ? _buildHub() : _buildPage(page),
        ),
      ),
    );
  }

  /// The landing page: a short list of categories that open focused sub-pages.
  Widget _buildHub() {
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Avatar(
                  url: widget.user.picture,
                  name: widget.user.name,
                  radius: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(widget.user.handle,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
            ],
          ),
        ),
        _card([
          _categoryTile('account', Icons.person_outline, 'Account',
              'Username, email, phone, password & 2FA'),
          const Divider(height: 1, indent: 56),
          _categoryTile('privacy', Icons.lock_outline, 'Privacy & safety',
              'Visibility, interactions & muted words'),
          const Divider(height: 1, indent: 56),
          _categoryTile('notifications', Icons.notifications_none,
              'Notifications', 'How we reach you'),
          const Divider(height: 1, indent: 56),
          _categoryTile('appearance', Icons.brightness_6_outlined,
              'Appearance', 'Theme, accent & stories'),
        ]),
        _card([
          _categoryTile('navigation', Icons.dashboard_customize_outlined,
              'Navigation', 'Bottom bar & sidebar'),
          const Divider(height: 1, indent: 56),
          _categoryTile('shortcuts', Icons.widgets_outlined,
              'Shortcuts & tools', 'Guides, roadside, ads, friends & more'),
          const Divider(height: 1, indent: 56),
          _categoryTile(
              'developer', Icons.code, 'Developer', 'API keys'),
        ]),
        const SizedBox(height: 12),
        _card([
          ListTile(
            leading: Icon(Icons.logout, color: error),
            title: Text('Sign out', style: TextStyle(color: error)),
            onTap: _signOut,
          ),
        ]),
      ],
    );
  }

  /// Builds the content for a single settings category.
  Widget _buildPage(String page) {
    final children = switch (page) {
      'account' => _accountChildren(),
      'privacy' => _privacyChildren(),
      'notifications' => _notificationsChildren(),
      'appearance' => _appearanceChildren(),
      'navigation' => _navigationChildren(),
      'shortcuts' => _shortcutsChildren(),
      'developer' => _developerChildren(),
      _ => const <Widget>[],
    };
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: children,
    );
  }

  List<Widget> _accountChildren() => [
        _card([
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('Username'),
            subtitle: Text(widget.user.handle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changeUsername,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Email'),
            subtitle: Text(widget.user.email),
            trailing: widget.user.emailVerified
                ? const Icon(Icons.verified,
                    color: Color(0xFF22C55E), size: 20)
                : TextButton(
                    onPressed: _verifyEmail, child: const Text('Verify')),
            onTap: _changeEmail,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(widget.user.phone?.isNotEmpty == true
                ? widget.user.phone!
                : 'Not set'),
            trailing: widget.user.phoneVerified
                ? const Icon(Icons.verified,
                    color: Color(0xFF22C55E), size: 20)
                : const Icon(Icons.chevron_right),
            onTap: _managePhone,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePassword,
          ),
        ]),
        _section('Security'),
        _card([
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('Two-factor authentication'),
            subtitle: const Text('Require a code at login'),
            value: _twofa,
            onChanged: _toggle2fa,
          ),
        ]),
      ];

  List<Widget> _privacyChildren() => [
        _section('Visibility'),
        _card([
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Private account'),
            subtitle: const Text('Only approved followers see your posts'),
            value: _private,
            onChanged: (v) => _toggle('is_private', v, (x) => _private = x),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.search),
            title: const Text('Searchable'),
            subtitle: const Text('Let people find you in search'),
            value: _searchable,
            onChanged: (v) => _toggle('searchable', v, (x) => _searchable = x),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide online status'),
            value: _hideOnline,
            onChanged: (v) => _toggle('hide_online', v, (x) => _hideOnline = x),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.favorite_border),
            title: const Text('Hide like counts'),
            subtitle: const Text('On posts you see across the app'),
            value: _hideLikes,
            onChanged: (v) => _toggle('hide_likes', v, (x) => _hideLikes = x),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.local_fire_department_outlined),
            title: const Text('Show activity points'),
            subtitle: const Text('Display your points on your profile'),
            value: _showPoints,
            onChanged: (v) => _toggle('show_points', v, (x) => _showPoints = x),
          ),
        ]),
        _section('Interactions'),
        _card([
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Who can message you'),
            trailing: Text(_policyLabels[_messagePolicy] ?? _messagePolicy),
            onTap: () => _pickPolicy('Who can message you', 'message_policy',
                _messagePolicy, (v) => _messagePolicy = v),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Who can tag you'),
            trailing: Text(_policyLabels[_tagPolicy] ?? _tagPolicy),
            onTap: () => _pickPolicy('Who can tag you', 'tag_policy',
                _tagPolicy, (v) => _tagPolicy = v),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.comment_outlined),
            title: const Text('Default reply policy'),
            subtitle: const Text('Applied to new posts'),
            trailing: Text(_policyLabels[_commentPolicy] ?? _commentPolicy),
            onTap: () => _pickPolicy('Default reply policy',
                'default_comment_policy', _commentPolicy,
                (v) => _commentPolicy = v),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Who sees your connections'),
            trailing: Text(_policyLabels[_connectionsVisibility] ??
                _connectionsVisibility),
            onTap: () => _pickPolicy('Who sees your connections',
                'connections_visibility', _connectionsVisibility,
                (v) => _connectionsVisibility = v),
          ),
        ]),
        _section('Muted keywords'),
        _card([
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in _muted)
                  InputChip(label: Text(k), onDeleted: () => _unmute(k)),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Mute a keyword'),
                  onPressed: _editMuted,
                ),
              ],
            ),
          ),
        ]),
      ];

  List<Widget> _notificationsChildren() => [
        _card([
          SwitchListTile(
            secondary: const Icon(Icons.sms_outlined),
            title: const Text('SMS notifications'),
            subtitle: const Text('Receive alerts by text message'),
            value: _sms,
            onChanged: (v) => _toggle('sms_notifications', v, (x) => _sms = x),
          ),
        ]),
      ];

  List<Widget> _appearanceChildren() => [
        _card([
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            trailing: Text(_themeLabel(themeController.value)),
            onTap: () async {
              await _pickTheme();
              if (mounted) setState(() {});
            },
          ),
          const Divider(height: 1, indent: 56),
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
          ValueListenableBuilder<bool>(
            valueListenable: hideStoriesController,
            builder: (context, hidden, _) => SwitchListTile(
              secondary: const Icon(Icons.auto_stories_outlined),
              title: const Text('Hide stories'),
              subtitle: const Text('Hide the stories row on your feed'),
              value: hidden,
              onChanged: (v) {
                hideStoriesController.set(v);
                api.auth.updateProfile({'hide_stories_row': v}).ignore();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.volume_off_outlined),
            title: const Text('Muted & priority words'),
            subtitle: const Text('Hide or boost posts by keyword'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MutedWordsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Verification'),
            subtitle: const Text('Email, phone & ID verification status'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DocumentsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.apps_outlined),
            title: const Text('Connected apps'),
            subtitle: const Text('Third-party apps with account access'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ConnectedAppsScreen())),
          ),
        ]),
      ];

  List<Widget> _navigationChildren() => [
        _card([
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Customize navigation'),
            subtitle: const Text('Choose your bottom bar (max 5)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CustomizeNavScreen())),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.view_sidebar_outlined),
            title: const Text('Customize sidebar'),
            subtitle: const Text('Choose your sidebar shortcuts (max 5)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CustomizeSidebarScreen())),
          ),
        ]),
      ];

  List<Widget> _shortcutsChildren() => [
        _card([
          _shortcut(Icons.collections_bookmark_outlined, 'Places & Guides',
              () => const GuidesScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.car_repair_outlined, 'Roadside assistance',
              () => const RoadsideScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.assignment_outlined, 'Forms',
              () => const FormsScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.sports_esports_outlined, 'Games',
              () => const GamesScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.campaign_outlined, 'Advertising',
              () => const AdsScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.monetization_on_outlined, 'Monetize',
              () => const MonetizeScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.leaderboard_outlined, 'Leaderboard',
              () => const LeaderboardScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.bookmark_outline, 'Bookmarks',
              () => const BookmarksScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.workspaces_outline, 'Circles',
              () => const CirclesScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.people_alt_outlined, 'Friends',
              () => const FriendsScreen()),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.group_add_outlined, 'Followers & following',
              () => ConnectionsScreen(userId: widget.user.userId)),
          const Divider(height: 1, indent: 56),
          _shortcut(Icons.support_agent_outlined, 'Help & support',
              () => const SupportScreen()),
        ]),
      ];

  List<Widget> _developerChildren() => [
        _card([
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('API keys'),
            subtitle: const Text('Generate keys for the OkaySpace API'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ApiKeysScreen(),
            )),
          ),
        ]),
      ];

  /// Wraps a group of tiles in a rounded card.
  Widget _card(List<Widget> children) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  /// A hub row that opens a settings sub-page.
  Widget _categoryTile(
          String id, IconData icon, String title, String subtitle) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _page = id),
      );

  /// A settings row that opens a screen.
  Widget _shortcut(IconData icon, String label, Widget Function() builder) =>
      ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => builder())),
      );
}

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog();

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_email.text.contains('@') || _password.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await api.auth.changeEmail(
        currentPassword: _password.text,
        newEmail: _email.text.trim(),
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
      title: const Text('Change email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'New email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Current password', border: OutlineInputBorder()),
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
