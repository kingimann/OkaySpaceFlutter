import 'package:flutter/material.dart';

import '../../okayspace_api.dart';
import 'common.dart';

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

  Future<void> _editBio(User user) async {
    final controller = TextEditingController(text: user.bio ?? '');
    final newBio = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit bio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (newBio == null) return;
    try {
      await api.auth.updateProfile({'bio': newBio});
      setState(() => _me = api.auth.me());
    } catch (e) {
      if (mounted) showError(context, e);
    }
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
              Center(child: Text(u.handle)),
              const SizedBox(height: 24),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Bio'),
                      subtitle: Text(u.bio ?? 'Add a bio'),
                      trailing: const Icon(Icons.edit, size: 18),
                      onTap: () => _editBio(u),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('Wallet'),
                      trailing: Text(
                          '${u.currency} ${u.walletBalance.toStringAsFixed(2)}'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.stars_outlined),
                      title: const Text('Level'),
                      trailing: Text('${u.levelTitle} · ${u.points} pts'),
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
