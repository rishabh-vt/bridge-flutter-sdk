/// Imperative API for [BridgeSdk].
abstract class BridgeSdkController {
  /// Re-fetches `/launch` and remounts the WebView.
  Future<void> reload();
}
