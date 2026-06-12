import 'nfc_pay_stub.dart' if (dart.library.io) 'nfc_pay_io.dart' as impl;

/// NFC tap-to-pay plumbing. Real on iOS/Android (via `nfc_manager`); the web
/// stub reports NFC as unavailable so callers can hide the feature.

/// Whether this device can scan NFC tags right now.
Future<bool> nfcAvailable() => impl.available();

/// Scans for a tag and returns the first URI found in its NDEF message, or
/// null when the tag carries none. Throws on session errors.
Future<Uri?> nfcReadUri() => impl.readUri();

/// Writes [uri] to the next writable tag held against the phone.
Future<void> nfcWriteUri(String uri) => impl.writeUri(uri);

/// Cancels an in-flight scan/write session (no-op when idle).
Future<void> nfcCancel() => impl.cancel();
