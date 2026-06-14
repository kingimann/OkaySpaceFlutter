import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'common.dart';

/// A simple in-app camera: open the device camera, take a photo, and review
/// the shots captured this session. Works on mobile and (capture-capable)
/// web browsers via the image picker.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _picker = ImagePicker();
  final List<Uint8List> _shots = [];
  bool _busy = false;

  Future<void> _capture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (shot != null) {
        final bytes = await shot.readAsBytes();
        if (mounted) setState(() => _shots.insert(0, bytes));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const OkayAppBar(title: Text('Camera')),
      // Lifted so it clears the floating bottom nav on pushed screens.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton.extended(
          onPressed: _busy ? null : _capture,
          icon: const Icon(Icons.photo_camera),
          label: Text(_shots.isEmpty ? 'Take a photo' : 'Take another'),
        ),
      ),
      body: _shots.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_camera_outlined,
                      size: 64, color: scheme.outline),
                  const SizedBox(height: 14),
                  const Text('Open the camera to take a photo',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Your shots appear here for this session.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _shots.length,
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => _preview(_shots[i]),
                  child: Image.memory(_shots[i], fit: BoxFit.cover),
                ),
              ),
            ),
    );
  }

  void _preview(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }
}
