import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../okayspace_api.dart';
import 'common.dart';

/// Composes and posts a new image story.
///
/// Pick a photo, optionally add a caption, then post via [api.stories.create].
/// Returns `true` via [Navigator] when a story was posted.
class StoryComposer extends StatefulWidget {
  /// Opens the photo picker, then this composer with the chosen image.
  /// Returns `true` if a story was posted. No-op if the user cancels.
  static Future<bool> start(BuildContext context) async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (file == null || !context.mounted) return false;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return false;
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StoryComposer._withImage(bytes),
    ));
    return posted ?? false;
  }

  const StoryComposer._withImage(this.bytes) : super(key: null);

  final Uint8List? bytes;

  @override
  State<StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<StoryComposer> {
  final _caption = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final bytes = widget.bytes;
    if (bytes == null || _posting) return;
    setState(() => _posting = true);
    try {
      await api.stories.create(
        StoryMedia(base64: base64Encode(bytes), type: 'image'),
        caption: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
      );
      if (mounted) {
        showInfo(context, 'Story posted');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const OkayAppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('New story'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : const Icon(Icons.image_not_supported,
                      color: Colors.white54, size: 64),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: TextStyle(color: Colors.white54),
                        filled: false,
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white54)),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _posting ? null : _post,
                    icon: _posting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Post'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
