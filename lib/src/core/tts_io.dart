// Native fallback: no built-in TTS without a plugin, so these are no-ops.
// Voice guidance currently targets the web build (browser SpeechSynthesis).
void ttsSpeak(String text) {}
void ttsStop() {}
