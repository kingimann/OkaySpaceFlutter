import 'dart:async';
import 'dart:convert';

import 'package:nfc_manager/nfc_manager.dart';

import 'nfc_cancelled.dart';

/// iOS/Android NFC implementation backed by `nfc_manager`.
///
/// The active completer is tracked so [cancel] can resolve it: the Android
/// plugin never fires onError, so without this a dismissed session would
/// leave callers awaiting forever.
Completer<Uri?>? _read;
Completer<void>? _write;

Future<bool> available() async {
  try {
    return await NfcManager.instance.isAvailable();
  } catch (_) {
    return false;
  }
}

Future<Uri?> readUri() {
  final completer = Completer<Uri?>();
  _read = completer;
  NfcManager.instance.startSession(
    alertMessage: 'Hold your phone near the pay tag',
    onDiscovered: (NfcTag tag) async {
      Uri? found;
      Object? error;
      try {
        final message = Ndef.from(tag)?.cachedMessage;
        for (final record in message?.records ?? const <NdefRecord>[]) {
          found = _decodeUri(record);
          if (found != null) break;
        }
      } catch (e) {
        error = e;
      }
      // Complete before stopping: stopSession can itself throw (e.g. an
      // already-invalidated iOS session) and must not orphan the caller.
      if (!completer.isCompleted) {
        error == null
            ? completer.complete(found)
            : completer.completeError(error);
      }
      try {
        await NfcManager.instance.stopSession(
            errorMessage: error == null ? null : 'Could not read the tag');
      } catch (_) {}
    },
    onError: (e) async => _failWith(completer, e),
  );
  return completer.future;
}

Future<void> writeUri(String uri) {
  final completer = Completer<void>();
  _write = completer;
  NfcManager.instance.startSession(
    alertMessage: 'Hold your phone near a writable tag',
    onDiscovered: (NfcTag tag) async {
      Object? error;
      try {
        final ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          throw Exception('This tag can\'t be written to');
        }
        await ndef.write(NdefMessage([NdefRecord.createUri(Uri.parse(uri))]));
      } catch (e) {
        error = e;
      }
      if (!completer.isCompleted) {
        error == null ? completer.complete() : completer.completeError(error);
      }
      try {
        await NfcManager.instance.stopSession(
            alertMessage: error == null ? 'Pay tag written' : null,
            errorMessage: error == null ? null : 'Could not write the tag');
      } catch (_) {}
    },
    onError: (e) async => _failWith(completer, e),
  );
  return completer.future;
}

/// Completes [completer] for an iOS session error; the system sheet's Cancel
/// (and timeouts) become [NfcCancelled] so the UI stays silent.
void _failWith(Completer<dynamic> completer, NfcError e) {
  if (completer.isCompleted) return;
  if (e.type == NfcErrorType.userCanceled ||
      e.type == NfcErrorType.sessionTimeout) {
    completer.completeError(const NfcCancelled());
  } else {
    completer.completeError(e);
  }
}

Future<void> cancel() async {
  final r = _read;
  final w = _write;
  if (r != null && !r.isCompleted) r.completeError(const NfcCancelled());
  if (w != null && !w.isCompleted) w.completeError(const NfcCancelled());
  try {
    await NfcManager.instance.stopSession();
  } catch (_) {/* session may not be running */}
}

/// Decodes an NDEF well-known URI ('U') record: the first payload byte is an
/// index into the standard prefix table, the rest is the UTF-8 URI body.
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
  return Uri.tryParse(prefix +
      utf8.decode(record.payload.sublist(1), allowMalformed: true));
}
