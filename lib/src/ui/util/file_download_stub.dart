/// Non-web: no universal file-download target. Returns false so the caller can
/// fall back (e.g. copy the data to the clipboard).
bool downloadText(String filename, String text) => false;
