import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart';
import 'package:okayspace/src/core/forms_e2e.dart';

void main() {
  test('passphrase setup → encrypt (as the browser would) → decrypt roundtrip',
      () async {
    const passphrase = 'correct horse battery staple';
    final s = await FormsE2E.setup(passphrase);

    // Simulate the public form (tweetnacl): ephemeral key + box to the owner
    // public key, formatted "epk:nonce:cipher".
    final ownerPub = PublicKey(base64Decode(s.publicKey));
    final eph = PrivateKey.generate();
    final box = Box(myPrivateKey: eph, theirPublicKey: ownerPub);
    final values = {'name': 'Alice', 'msg': 'secret answer'};
    final enc = box.encrypt(utf8.encode(jsonEncode(values)));
    final blob = '${base64Encode(eph.publicKey.toList())}:'
        '${base64Encode(enc.nonce)}:${base64Encode(enc.cipherText)}';

    final out = await FormsE2E.decrypt(blob, s.salt, passphrase);
    expect(out, values);

    // Wrong passphrase can't decrypt.
    final bad = await FormsE2E.decrypt(blob, s.salt, 'wrong');
    expect(bad, isNull);
  });
}
