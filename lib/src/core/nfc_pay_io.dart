import 'dart:async';

import 'package:nfc_manager/nfc_manager.dart';

/// iOS/Android NFC implementation backed by `nfc_manager`.

Future<bool> available() async {
  try {
    return await NfcManager.instance.isAvailable();
  } catch (_) {
    return false;
  }
}

Future<Uri?> readUri() {
  final completer = Completer<Uri?>();
  NfcManager.instance.startSession(
    alertMessage: 'Hold your phone near the pay tag',
    onDiscovered: (NfcTag tag) async {
      try {
        final message = Ndef.from(tag)?.cachedMessage;
        Uri? found;
        for (final record in message?.records ?? const <NdefRecord>[]) {
          found = _decodeUri(record);
          if (found != null) break;
        }
        await NfcManager.instance.stopSession();
        if (!completer.isCompleted) completer.complete(found);
      } catch (e) {
        await NfcManager.instance
            .stopSession(errorMessage: 'Could not read the tag');
        if (!completer.isCompleted) completer.completeError(e);
      }
    },
    onError: (e) async {
      if (!completer.isCompleted) completer.completeError(e);
    },
  );
  return completer.future;
}

Future<void> writeUri(String uri) {
  final completer = Completer<void>();
  NfcManager.instance.startSession(
    alertMessage: 'Hold your phone near a writable tag',
    onDiscovered: (NfcTag tag) async {
      try {
        final ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          throw Exception('This tag can\'t be written to');
        }
        await ndef.write(NdefMessage([NdefRecord.createUri(Uri.parse(uri))]));
        await NfcManager.instance.stopSession(alertMessage: 'Pay tag written');
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        await NfcManager.instance
            .stopSession(errorMessage: 'Could not write the tag');
        if (!completer.isCompleted) completer.completeError(e);
      }
    },
    onError: (e) async {
      if (!completer.isCompleted) completer.completeError(e);
    },
  );
  return completer.future;
}

Future<void> cancel() async {
  try {
    await NfcManager.instance.stopSession();
  } catch (_) {/* session may not be running */}
}

/// Decodes an NDEF well-known URI ('U') record: the first payload byte is an
/// index into the standard prefix table, the rest is the URI body.
Uri? _decodeUri(NdefRecord record) {
  if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown ||
      record.type.length != 1 ||
      record.type.first != 0x55 ||
      record.payload.isEmpty) {
    return null;
  }
  final prefixIndex = record.payload.first;
  final prefix = prefixIndex < NdefRecord.URI_PREFIX_LIST.length
      ? NdefRecord.URI_PREFIX_LIST[prefixIndex]
      : '';
  return Uri.tryParse(prefix + String.fromCharCodes(record.payload.skip(1)));
}
