enum SdkErrorCode {
  invalidConfig,
  webviewLoadFailed,
  webviewRenderProcessGone,
  storageFailed,
  messageParseFailed,
  checkoutFailed,
}

extension SdkErrorCodeWire on SdkErrorCode {
  /// Wire format matching the React Native SDK error codes.
  String get wireName => switch (this) {
        SdkErrorCode.invalidConfig => 'INVALID_CONFIG',
        SdkErrorCode.webviewLoadFailed => 'WEBVIEW_LOAD_FAILED',
        SdkErrorCode.webviewRenderProcessGone => 'WEBVIEW_RENDER_PROCESS_GONE',
        SdkErrorCode.storageFailed => 'STORAGE_FAILED',
        SdkErrorCode.messageParseFailed => 'MESSAGE_PARSE_FAILED',
        SdkErrorCode.checkoutFailed => 'CHECKOUT_FAILED',
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
