// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Speaks [text] via the browser's SpeechSynthesis API (no plugin needed).
/// Cancels any in-progress utterance first so guidance never piles up.
void ttsSpeak(String text) {
  try {
    final synth = html.window.speechSynthesis;
    if (synth == null || text.isEmpty) return;
    synth.cancel();
    final u = html.SpeechSynthesisUtterance(text)
      ..rate = 1.0
      ..pitch = 1.0
      ..volume = 1.0;
    synth.speak(u);
  } catch (_) {/* speech is best-effort */}
}

void ttsStop() {
  try {
    html.window.speechSynthesis?.cancel();
  } catch (_) {}
}
