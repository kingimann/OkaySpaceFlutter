/// Thrown by the NFC layer when a scan/write is cancelled — by the user
/// dismissing the waiting UI, the iOS system sheet's Cancel, or a session
/// timeout. Callers should swallow it silently.
class NfcCancelled implements Exception {
  const NfcCancelled();
}
