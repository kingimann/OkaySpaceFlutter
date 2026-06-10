import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Create a marketplace listing. Returns the created [Listing] via Navigator.
class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  final _locality = TextEditingController();
  String _category = 'other';
  String? _condition = 'good';
  bool _negotiable = false;
  final List<Uint8List> _photos = [];
  bool _busy = false;

  static const _categories = [
    'electronics', 'furniture', 'vehicles', 'clothing', 'home',
    'sports', 'toys', 'books', 'services', 'other',
  ];
  static const _conditions = ['new', 'like_new', 'good', 'fair', 'poor'];

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
    _locality.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final files =
        await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 85);
    for (final f in files) {
      _photos.add(await f.readAsBytes());
    }
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    final price = num.tryParse(_price.text.trim()) ?? 0;
    if (_title.text.trim().isEmpty) {
      showInfo(context, 'Add a title');
      return;
    }
    setState(() => _busy = true);
    try {
      final listing = await api.marketplace.create(ListingCreate(
        title: _title.text.trim(),
        price: price,
        category: _category,
        condition: _condition,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        locality:
            _locality.text.trim().isEmpty ? null : _locality.text.trim(),
        negotiable: _negotiable,
        photos: _photos.map(base64Encode).toList(),
      ));
      if (mounted) Navigator.of(context).pop(listing);
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
        title: const Text('New listing'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: _photos.isEmpty ? 0 : 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_photos[i],
                      width: 100, height: 100, fit: BoxFit.cover),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _photos.removeAt(i)),
                    child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child:
                            Icon(Icons.close, size: 14, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _addPhotos,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add photos'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Price',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
                labelText: 'Category', border: OutlineInputBorder()),
            items: [
              for (final c in _categories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _condition,
            decoration: const InputDecoration(
                labelText: 'Condition', border: OutlineInputBorder()),
            items: [
              for (final c in _conditions)
                DropdownMenuItem(value: c, child: Text(c.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => _condition = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locality,
            decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'Description', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            value: _negotiable,
            onChanged: (v) => setState(() => _negotiable = v),
            title: const Text('Price negotiable'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
