import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import 'common.dart';

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

  /// Locally-picked avatar / cover bytes, shown as previews until saved.
  Uint8List? _newPicture;
  Uint8List? _newCover;
  bool _busy = false;

  Future<void> _pickPicture() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _newPicture = bytes);
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
      };
      if (_birthday != null) {
        patch['birthday'] =
            _birthday!.toIso8601String().split('T').first;
      }
      if (_newPicture != null) {
        patch['picture'] =
            'data:image/jpeg;base64,${base64Encode(_newPicture!)}';
      }
      if (_newCover != null) {
        patch['cover_photo'] =
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      ),
      body: MaxWidth(
        child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Cover photo with the avatar overlapping its bottom edge.
          SizedBox(
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
                            onTap: _pickPicture,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.camera_alt,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
          SwitchListTile(
            value: _private,
            onChanged: (v) => setState(() => _private = v),
            title: const Text('Private account'),
            subtitle:
                const Text('Only approved followers can see your posts'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      ),
    );
  }
}
