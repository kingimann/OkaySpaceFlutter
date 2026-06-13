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

/// The result of a video upload: the playable URL, a derived poster image,
/// and the source dimensions/duration when Cloudinary reports them.
typedef VideoUpload = ({
  String? url,
  String? thumbnail,
  int? width,
  int? height,
  double? duration,
});

const VideoUpload _noVideo =
    (url: null, thumbnail: null, width: null, height: null, duration: null);

/// Uploads video bytes to Cloudinary and returns the hosted URL plus a
/// generated poster frame (so the video card has a thumbnail). Returns nulls
/// when Cloudinary isn't configured or the upload fails.
Future<VideoUpload> cloudinaryUploadVideo(Uint8List bytes,
    {String folder = 'videos'}) async {
  if (!hasCloudinary) return _noVideo;
  try {
    final dataUri = 'data:video/mp4;base64,${base64Encode(bytes)}';
    final res = await sendHttp(HttpRequestData(
      method: 'POST',
      url: Uri.parse(
          'https://api.cloudinary.com/v1_1/$kCloudinaryCloud/video/upload'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: 'upload_preset=${Uri.encodeQueryComponent(kCloudinaryPreset)}'
          '&folder=${Uri.encodeQueryComponent(folder)}'
          '&file=${Uri.encodeQueryComponent(dataUri)}',
      // Videos are large; give the upload room before timing out.
      timeout: const Duration(minutes: 8),
    ));
    if (res.status >= 400) return _noVideo;
    final data = jsonDecode(res.body);
    if (data is! Map) return _noVideo;
    final url = data['secure_url'] ?? data['url'];
    if (url is! String || !url.startsWith('http')) return _noVideo;
    // Cloudinary serves a poster frame at the same public id with a still
    // image extension: insert so_0 (start offset) and swap the extension.
    final thumb = url
        .replaceFirst('/upload/', '/upload/so_0/')
        .replaceFirst(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');
    return (
      url: url,
      thumbnail: thumb,
      width: data['width'] is num ? (data['width'] as num).toInt() : null,
      height: data['height'] is num ? (data['height'] as num).toInt() : null,
      duration:
          data['duration'] is num ? (data['duration'] as num).toDouble() : null,
    );
  } catch (_) {
    return _noVideo;
  }
}
