import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart' hide PublicKey;
import 'package:pinenacl/x25519.dart';

/// End-to-end encryption for form responses (NaCl box / X25519, libsodium-
/// compatible so it interoperates with tweetnacl in the public form page).
///
/// The owner's keypair is derived deterministically from a **passphrase** plus
/// a non-secret per-form **salt**. The passphrase never leaves the device; the
/// server only ever stores the public key, the salt, and ciphertext it can't
/// read.
class FormsE2E {
  static Future<PrivateKey> _privateKey(String passphrase, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);
    final key = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
    return PrivateKey(Uint8List.fromList(await key.extractBytes()));
  }

  /// Sets up E2E for a form: returns the public key + salt (both base64) to
  /// store on the form. The passphrase is never returned to the server.
  static Future<({String publicKey, String salt})> setup(
      String passphrase) async {
    final salt = Uint8List.fromList(
        List.generate(16, (_) => Random.secure().nextInt(256)));
    final sk = await _privateKey(passphrase, salt);
    return (
      publicKey: base64Encode(sk.publicKey.toList()),
      salt: base64Encode(salt),
    );
  }

  /// Decrypts an E2E response blob ("epk:nonce:cipher", base64 parts) into its
  /// JSON values map, given the form's salt and the owner's passphrase. Returns
  /// null if the passphrase is wrong or the blob is malformed.
  static Future<Map<String, dynamic>?> decrypt(
      String blob, String saltB64, String passphrase) async {
    try {
      final parts = blob.split(':');
      if (parts.length != 3) return null;
      final sk = await _privateKey(passphrase, base64Decode(saltB64));
      final box = Box(
          myPrivateKey: sk, theirPublicKey: PublicKey(base64Decode(parts[0])));
      final plain = box.decrypt(EncryptedMessage(
          nonce: base64Decode(parts[1]), cipherText: base64Decode(parts[2])));
      final m = jsonDecode(utf8.decode(plain));
      return m is Map ? m.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }
}
