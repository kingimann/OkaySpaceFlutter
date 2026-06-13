import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import '../core/avatar_gen.dart';
import '../core/cloudinary_api.dart';
import 'common.dart';
import 'profile_decor.dart';

/// Edits the signed-in user's profile fields. Returns `true` via [Navigator]
/// when changes were saved.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final User user;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user.name);
  late final TextEditingController _headline =
      TextEditingController(text: widget.user.headline ?? '');
  late final TextEditingController _bio =
      TextEditingController(text: widget.user.bio ?? '');
  late final TextEditingController _location =
      TextEditingController(text: widget.user.location ?? '');
  late final TextEditingController _pronouns =
      TextEditingController(text: '${widget.user.raw['pronouns'] ?? ''}');
  late final TextEditingController _status =
      TextEditingController(text: '${widget.user.raw['status'] ?? ''}');
  late bool _private = widget.user.isPrivate;
  late final List<String> _interests = List.of(widget.user.interests);
  late DateTime? _birthday =
      DateTime.tryParse('${widget.user.raw['birthday'] ?? ''}');

  // Social links (the profile renders these as tappable icons).
  static const _socialPlatforms = <String, (String, IconData)>{
    'website': ('Website', Icons.language),
    'twitter': ('X / Twitter', Icons.alternate_email),
    'instagram': ('Instagram', Icons.camera_alt_outlined),
    'tiktok': ('TikTok', Icons.music_note),
    'youtube': ('YouTube', Icons.play_circle_outline),
    'github': ('GitHub', Icons.code),
    'linkedin': ('LinkedIn', Icons.business_center_outlined),
    'facebook': ('Facebook', Icons.facebook),
  };
  late final Map<String, TextEditingController> _socials = {
    for (final k in _socialPlatforms.keys)
      k: TextEditingController(text: _initialSocial(k)),
  };

  String _initialSocial(String key) {
    final raw = widget.user.raw['socials'] ??
        widget.user.raw['links'] ??
        widget.user.raw['social_links'];
    if (raw is Map && raw[key] != null) return '${raw[key]}';
    return '';
  }

  /// Locally-picked avatar / cover bytes, shown as previews until saved.
  Uint8List? _newPicture;
  Uint8List? _newCover;
  /// A generated (DiceBear) avatar URL chosen instead of an uploaded photo.
  String? _generatedAvatarUrl;
  bool _busy = false;

  Future<void> _pickPicture() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() {
        _newPicture = bytes;
        _generatedAvatarUrl = null; // a real photo overrides a generated one
      });
    }
  }

  /// One sheet: a grid of generated avatars (DiceBear images served as plain
  /// <img>, so they work on every web renderer + mobile) to tap, a style
  /// filter, More, and Upload. Opens instantly — no on-device image encoding
  /// (which could hang on mobile Safari and make the button "do nothing").
  Future<void> _changeAvatar() async {
    String? style; // null = "Surprise me" (mixed styles)
    var urls = avatarBatch(style: style);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.75,
                maxChildSize: 0.95,
                builder: (_, scrollCtrl) => Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text('Tap a picture to use it',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: const Text('Surprise me'),
                              selected: style == null,
                              onSelected: (_) => setSheet(() {
                                style = null;
                                urls = avatarBatch(style: style);
                              }),
                            ),
                          ),
                          for (final st in kAvatarStyles)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(st.label),
                                selected: style == st.id,
                                onSelected: (_) => setSheet(() {
                                  style = st.id;
                                  urls = avatarBatch(style: st.id);
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: urls.length,
                        itemBuilder: (context, i) => Material(
                          color: scheme.surfaceContainerHighest,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _generatedAvatarUrl = urls[i];
                                _newPicture = null;
                              });
                              Navigator.pop(sheetContext);
                            },
                            child: Image.network(
                              urls[i],
                              fit: BoxFit.cover,
                              loadingBuilder: (_, child, progress) =>
                                  progress == null
                                      ? child
                                      : const Center(
                                          child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))),
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.person, color: scheme.outline),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setSheet(
                                  () => urls = avatarBatch(style: style)),
                              icon: const Icon(Icons.refresh),
                              label: const Text('More'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _pickPicture();
                              },
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Upload'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickCover() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _newCover = bytes);
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _birthday = picked);
  }

  Future<void> _addInterest() async {
    final tag = await promptText(context,
        title: 'Add interest', hint: 'e.g. photography', action: 'Add');
    if (tag == null) return;
    final clean = tag.replaceFirst('#', '').trim().toLowerCase();
    if (clean.isNotEmpty && !_interests.contains(clean)) {
      setState(() => _interests.add(clean));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _headline.dispose();
    _bio.dispose();
    _location.dispose();
    _pronouns.dispose();
    _status.dispose();
    for (final c in _socials.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'headline': _headline.text.trim(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
        'pronouns': _pronouns.text.trim(),
        'status': _status.text.trim(),
        'interests': _interests,
        'is_private': _private,
        'socials': {
          for (final e in _socials.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        },
      };
      if (_birthday != null) {
        patch['birthday'] =
            _birthday!.toIso8601String().split('T').first;
      }
      if (_newPicture != null) {
        patch['picture'] =
            await cloudinaryUploadImage(_newPicture!, folder: 'avatars') ??
                'data:image/jpeg;base64,${base64Encode(_newPicture!)}';
      } else if (_generatedAvatarUrl != null) {
        // A generated avatar is already a hosted URL — store it directly.
        patch['picture'] = _generatedAvatarUrl;
      }
      if (_newCover != null) {
        patch['cover_photo'] =
            await cloudinaryUploadImage(_newCover!, folder: 'covers') ??
                'data:image/jpeg;base64,${base64Encode(_newCover!)}';
      }
      await api.auth.updateProfile(patch);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cover photo with the avatar overlapping its bottom edge (Basics tab).
  Widget _coverAvatarHeader() {
    return SizedBox(
      height: 168,
      child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _pickCover,
                  child: Container(
                    height: 130,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      image: _newCover != null
                          ? DecorationImage(
                              image: MemoryImage(_newCover!),
                              fit: BoxFit.cover)
                          : (widget.user.coverPhoto != null &&
                                  widget.user.coverPhoto!.isNotEmpty)
                              ? DecorationImage(
                                  image:
                                      NetworkImage(widget.user.coverPhoto!),
                                  fit: BoxFit.cover)
                              : null,
                    ),
                    child: const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.black45,
                          child: Icon(Icons.photo_camera,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _changeAvatar,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                width: 3),
                          ),
                          child: _newPicture != null
                              ? CircleAvatar(
                                  radius: 38,
                                  backgroundImage: MemoryImage(_newPicture!))
                              : _generatedAvatarUrl != null
                                  ? CircleAvatar(
                                      radius: 38,
                                      backgroundImage:
                                          NetworkImage(_generatedAvatarUrl!))
                                  : Avatar(
                                      url: widget.user.picture,
                                      name: widget.user.name,
                                      radius: 38),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Material(
                            color: Theme.of(context).colorScheme.primary,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _changeAvatar,
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.edit,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: OkayAppBar(
          title: const Text('Edit profile'),
          actions: [
            TextButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Basics'),
              Tab(text: 'Look'),
              Tab(text: 'About'),
              Tab(text: 'Links'),
              Tab(text: 'Privacy'),
            ],
          ),
        ),
        body: MaxWidth(
          child: TabBarView(
            children: [
              _basicsTab(),
              _lookTab(),
              _aboutTab(),
              _linksTab(),
              _privacyTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _basicsTab() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _coverAvatarHeader(),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _headline,
            decoration: const InputDecoration(
                labelText: 'Headline',
                hintText: 'A short tagline',
                border: OutlineInputBorder()),
          ),
        ],
      );

  Widget _lookTab() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Appearance',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme, avatar frame & background'),
            subtitle: const Text('Customize how your profile looks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showProfileDecorSheet(context),
          ),
        ],
      );

  Widget _aboutTab() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _bio,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'Bio', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _status,
            maxLength: 80,
            decoration: const InputDecoration(
                labelText: 'Status',
                hintText: '☕ What are you up to?',
                prefixIcon: Icon(Icons.mood_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pronouns,
            decoration: const InputDecoration(
                labelText: 'Pronouns',
                hintText: 'e.g. they/them',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cake_outlined),
            title: const Text('Birthday'),
            subtitle: Text(_birthday != null
                ? '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}'
                : 'Not set'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickBirthday,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Interests',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _interests)
                InputChip(
                  label: Text('#$tag'),
                  onDeleted: () => setState(() => _interests.remove(tag)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: _addInterest,
              ),
            ],
          ),
        ],
      );

  Widget _linksTab() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final e in _socialPlatforms.entries) ...[
            TextField(
              controller: _socials[e.key],
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: e.value.$1,
                hintText: e.key == 'website' ? 'https://…' : '@handle or URL',
                prefixIcon: Icon(e.value.$2),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      );

  Widget _privacyTab() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            value: _private,
            onChanged: (v) => setState(() => _private = v),
            title: const Text('Private account'),
            subtitle:
                const Text('Only approved followers can see your posts'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      );
}
