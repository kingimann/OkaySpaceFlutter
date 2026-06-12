import 'dart:convert';
import 'dart:typed_data';

import 'http_transport.dart';

/// Cloudinary direct (unsigned) image uploads.
///
/// Uses an *unsigned upload preset*, which is designed for client-side use —
/// no secret ships in the app. Configure at build time:
///
///   --dart-define=CLOUDINARY_CLOUD_NAME=your-cloud
///   --dart-define=CLOUDINARY_UPLOAD_PRESET=your-unsigned-preset
///
/// (Cloudinary dashboard → Settings → Upload → Upload presets → add an
/// **unsigned** preset.) Without both values, callers fall back to inlining
/// base64 through the OkaySpace backend exactly as before.
const kCloudinaryCloud = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const kCloudinaryPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

bool get hasCloudinary =>
    kCloudinaryCloud.isNotEmpty && kCloudinaryPreset.isNotEmpty;

/// Uploads JPEG bytes straight to Cloudinary and returns the hosted https
/// URL. Returns null when Cloudinary isn't configured or the upload fails,
/// so callers can fall back to inline base64 — an upload hiccup must never
/// block posting.
Future<String?> cloudinaryUploadImage(Uint8List bytes,
    {String folder = 'okayspace'}) async {
  if (!hasCloudinary) return null;
  try {
    final dataUri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    final res = await sendHttp(HttpRequestData(
      method: 'POST',
      url: Uri.parse(
          'https://api.cloudinary.com/v1_1/$kCloudinaryCloud/image/upload'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: 'upload_preset=${Uri.encodeQueryComponent(kCloudinaryPreset)}'
          '&folder=${Uri.encodeQueryComponent(folder)}'
          '&file=${Uri.encodeQueryComponent(dataUri)}',
      timeout: const Duration(seconds: 60),
    ));
    if (res.status >= 400) return null;
    final data = jsonDecode(res.body);
    final url = data is Map ? (data['secure_url'] ?? data['url']) : null;
    return url is String && url.startsWith('http') ? url : null;
  } catch (_) {
    return null;
  }
}
