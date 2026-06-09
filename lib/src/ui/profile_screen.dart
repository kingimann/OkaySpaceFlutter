import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';
import 'communities_screen.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';
import 'groups_screen.dart';
import 'roadside_screen.dart';
import 'support_screen.dart';
import 'wallet_screen.dart';

/// Public profile of another user, with a follow toggle.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.userId});

  final String userId;

  /// Pushes this screen onto the navigator.
  static Future<void> open(BuildContext context, String userId) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ));

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<PublicUser> _profile;
  bool _following = false;

  @override
  void initState() {
    super.initState();
    _profile = _load();
  }

  Future<PublicUser> _load() async {
    final user = await api.users.publicProfile(widget.userId);
    _following = user.isFollowing;
    return user;
  }

  Future<void> _toggleFollow() async {
    setState(() => _following = !_following);
    try {
      await api.users.follow(widget.userId);
    } catch (e) {
      if (mounted) {
        setState(() => _following = !_following);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<PublicUser>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CenteredMessage(message: messageFor(snapshot.error));
          }
          final u = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Avatar(url: u.picture, name: u.name, radius: 48)),
              const SizedBox(height: 16),
              Center(
                child: Text(u.name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              if (u.username != null)
                Center(child: Text(u.handle)),
              if (u.headline != null) ...[
                const SizedBox(height: 8),
                Center(child: Text(u.headline!)),
              ],
              if (u.bio != null) ...[
                const SizedBox(height: 16),
                Text(u.bio!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: _toggleFollow,
                child: Text(_following ? 'Following' : 'Follow'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The signed-in user's own profile (read-only fields + sign out).
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  late Future<User> _me;

  @override
  void initState() {
    super.initState();
    _me = api.auth.me();
  }

  Future<void> _signOut() async {
    await api.auth.logout();
    widget.onSignedOut();
  }

  Future<void> _editProfile(User user) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EditProfileScreen(user: user),
    ));
    if (saved == true && mounted) setState(() => _me = api.auth.me());
  }

  Future<void> _pickTheme() async {
    final current = themeController.value;
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold))),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12, left: 4),
                child: Text('Accent color',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final a in kAccents)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, a.color),
                      child: Column(
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
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
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: FutureBuilder<User>(
        future: _me,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return CenteredMessage(
                message: messageFor(snapshot.error), icon: Icons.error_outline);
          }
          final u = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(child: Avatar(url: u.picture, name: u.name, radius: 48)),
              const SizedBox(height: 16),
              Center(
                child: Text(u.name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              Center(child: Text(u.handle)),
              if (u.headline != null && u.headline!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Center(child: Text(u.headline!)),
              ],
              if (u.bio != null && u.bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(u.bio!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _editProfile(u),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.people_alt_outlined),
                      title: const Text('Friends'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FriendsScreen(),
                      )),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Wallet'),
                      subtitle: Text(
                          '${u.currency} ${u.walletBalance.toStringAsFixed(2)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const WalletScreen(),
                      )),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: const Text('Communities'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CommunitiesScreen(),
                      )),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.group_work_outlined),
                      title: const Text('Groups'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const GroupsScreen(),
                      )),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.car_repair),
                      title: const Text('Roadside assistance'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RoadsideScreen(),
                      )),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.support_agent_outlined),
                      title: const Text('Support'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SupportScreen(),
                      )),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.stars_outlined),
                      title: const Text('Level'),
                      trailing: Text('${u.levelTitle} · ${u.points} pts'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.brightness_6_outlined),
                      title: const Text('Appearance'),
                      trailing: Text(_themeLabel(themeController.value)),
                      onTap: _pickTheme,
                    ),
                    const Divider(height: 1),
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
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
