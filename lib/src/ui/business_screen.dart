import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/cloudinary_api.dart';
import 'common.dart';

/// Manage the user's business storefront: create, edit, or close it.
/// A storefront sells under its own name/branding, separate from the
/// personal profile, and earns its own reviews.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _bio = TextEditingController();
  final _category = TextEditingController();
  final _location = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _policies = TextEditingController();

  Map<String, dynamic> _business = const {};
  Uint8List? _newLogo;
  Uint8List? _newBanner;
  bool _loading = true;
  bool _busy = false;

  bool get _exists => '${_business['id'] ?? ''}'.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await api.marketplace.myBusiness();
      if (!mounted) return;
      setState(() {
        _business = b;
        _name.text = '${b['name'] ?? ''}';
        _tagline.text = '${b['tagline'] ?? ''}';
        _bio.text = '${b['bio'] ?? ''}';
        _category.text = '${b['category'] ?? ''}';
        _location.text = '${b['location'] ?? ''}';
        _email.text = '${b['contact_email'] ?? ''}';
        _phone.text = '${b['contact_phone'] ?? ''}';
        _website.text = '${b['website'] ?? ''}';
        _policies.text = '${b['policies'] ?? ''}';
        _loading = false;
      });
    } catch (_) {
      // 404 = no storefront yet; show the empty form.
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _tagline, _bio, _category, _location,
      _email, _phone, _website, _policies,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Uint8List?> _pickImage({double maxWidth = 800}) async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: 85);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showInfo(context, 'Give your storefront a name.');
      return;
    }
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'tagline': _tagline.text.trim(),
        'bio': _bio.text.trim(),
        'category': _category.text.trim(),
        'location': _location.text.trim(),
        'contact_email': _email.text.trim(),
        'contact_phone': _phone.text.trim(),
        'website': _website.text.trim(),
        'policies': _policies.text.trim(),
      };
      if (_newLogo != null) {
        patch['logo'] =
            await cloudinaryUploadImage(_newLogo!, folder: 'business') ??
                'data:image/jpeg;base64,${base64Encode(_newLogo!)}';
      }
      if (_newBanner != null) {
        patch['banner'] =
            await cloudinaryUploadImage(_newBanner!, folder: 'business') ??
                'data:image/jpeg;base64,${base64Encode(_newBanner!)}';
      }
      await api.marketplace.upsertBusiness(patch);
      if (mounted) {
        showInfo(context, _exists ? 'Storefront updated' : 'Storefront created');
        await _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close storefront?'),
        content: const Text(
            'Your business profile and its reviews will be removed. '
            'Listings revert to your personal profile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close storefront')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.marketplace.deleteBusiness();
      if (mounted) {
        showInfo(context, 'Storefront closed');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rating = _business['rating'];
    final reviewCount = _business['review_count'];
    return Scaffold(
      appBar: OkayAppBar(
        title: Text(_exists ? 'My storefront' : 'Open a storefront'),
        actions: [
          if (_exists)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'close') _close();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'close', child: Text('Close storefront')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : MaxWidth(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Banner + logo pickers.
                  SizedBox(
                    height: 150,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final b = await _pickImage(maxWidth: 1600);
                            if (b != null && mounted) {
                              setState(() => _newBanner = b);
                            }
                          },
                          child: Container(
                            height: 110,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              image: _newBanner != null
                                  ? DecorationImage(
                                      image: MemoryImage(_newBanner!),
                                      fit: BoxFit.cover)
                                  : '${_business['banner'] ?? ''}'.isNotEmpty
                                      ? DecorationImage(
                                          image: NetworkImage(
                                              '${_business['banner']}'),
                                          fit: BoxFit.cover)
                                      : null,
                            ),
                            child: const Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.black45,
                                  child: Icon(Icons.photo_camera,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () async {
                              final b = await _pickImage();
                              if (b != null && mounted) {
                                setState(() => _newLogo = b);
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Theme.of(context)
                                        .scaffoldBackgroundColor,
                                    width: 3),
                              ),
                              child: _newLogo != null
                                  ? CircleAvatar(
                                      radius: 34,
                                      backgroundImage:
                                          MemoryImage(_newLogo!))
                                  : Avatar(
                                      url: '${_business['logo'] ?? ''}',
                                      name: _name.text.isEmpty
                                          ? 'B'
                                          : _name.text,
                                      radius: 34),
                            ),
                          ),
                        ),
                        if (rating != null)
                          Positioned(
                            right: 0,
                            bottom: 4,
                            child: Row(
                              children: [
                                const Icon(Icons.star,
                                    size: 18, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 4),
                                Text(
                                    '$rating · ${reviewCount ?? 0} reviews',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'Business name',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _tagline,
                    decoration: const InputDecoration(
                        labelText: 'Tagline',
                        hintText: 'A short slogan',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'About', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _category,
                          decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _location,
                          decoration: const InputDecoration(
                              labelText: 'Location',
                              border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Contact email',
                        prefixIcon: Icon(Icons.mail_outline),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Contact phone',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _website,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'Website',
                        prefixIcon: Icon(Icons.link),
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _policies,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Policies',
                        hintText: 'Returns, shipping, payment…',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.storefront),
                    label: Text(
                        _exists ? 'Save storefront' : 'Open storefront'),
                  ),
                ],
              ),
            ),
    );
  }
}
