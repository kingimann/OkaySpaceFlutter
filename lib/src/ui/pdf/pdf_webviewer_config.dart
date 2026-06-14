/// Apryse WebViewer configuration for the advanced (Acrobat-grade) PDF editor.
///
/// WebViewer is the only browser engine that does true in-place text editing.
/// To avoid self-hosting its ~100MB of assets, it loads everything from a CDN
/// by default (jsDelivr serving the published `@pdftron/webviewer` package), so
/// nothing needs to be hosted in this repo.
///
/// Two optional build-time overrides:
///   * APRYSE_LICENSE_KEY — your Apryse key. Without it WebViewer runs in
///     watermarked trial mode.
///   * APRYSE_PATH — point at Apryse's own CDN or your own host instead of the
///     jsDelivr default.
///
/// Example:
///   flutter build web \
///     --dart-define=APRYSE_LICENSE_KEY=your_key_here
const String kApryseVersion = '10.12.0';

const String kAprysePath = String.fromEnvironment(
  'APRYSE_PATH',
  defaultValue:
      'https://cdn.jsdelivr.net/npm/@pdftron/webviewer@$kApryseVersion/public',
);

const String kApryseLicenseKey =
    String.fromEnvironment('APRYSE_LICENSE_KEY', defaultValue: '');
