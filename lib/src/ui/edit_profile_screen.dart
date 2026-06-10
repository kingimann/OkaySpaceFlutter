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
  late bool _private = widget.user.isPrivate;

  /// Locally-picked avatar bytes, shown as a preview until saved.
  Uint8List? _newPicture;
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

  @override
  void dispose() {
    _name.dispose();
    _headline.dispose();
    _bio.dispose();
    _location.dispose();
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
        'is_private': _private,
      };
      if (_newPicture != null) {
        patch['picture'] =
            'data:image/jpeg;base64,${base64Encode(_newPicture!)}';
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
      appBar: AppBar(
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
          Center(
            child: Stack(
              children: [
                if (_newPicture != null)
                  CircleAvatar(
                      radius: 44, backgroundImage: MemoryImage(_newPicture!))
                else
                  Avatar(
                      url: widget.user.picture,
                      name: widget.user.name,
                      radius: 44),
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
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.camera_alt,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
