enum SdkErrorCode {
  invalidConfig,
  launchFailed,
  webviewLoadFailed,
}

extension SdkErrorCodeWire on SdkErrorCode {
  /// Wire format for host diagnostics.
  String get wireName => switch (this) {
        SdkErrorCode.invalidConfig => 'INVALID_CONFIG',
        SdkErrorCode.launchFailed => 'LAUNCH_FAILED',
        SdkErrorCode.webviewLoadFailed => 'WEBVIEW_LOAD_FAILED',
      };
}

class SdkError implements Exception {
  SdkError(this.code, this.message, [this.details]);

  final SdkErrorCode code;
  final String message;
  final Object? details;

  @override
  String toString() => 'SdkError(${code.wireName}): $message';
}
