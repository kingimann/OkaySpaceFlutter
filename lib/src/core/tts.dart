import 'tts_io.dart' if (dart.library.html) 'tts_web.dart' as impl;

/// Spoken turn-by-turn guidance. On the web this uses the browser's built-in
/// SpeechSynthesis; on native it is currently a no-op (no plugin dependency).
void speak(String text) => impl.ttsSpeak(text);

/// Stops any in-progress speech (e.g. when navigation ends).
void stopSpeaking() => impl.ttsStop();
