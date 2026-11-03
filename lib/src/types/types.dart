/// Auth tokens persisted and injected into the WebView.
typedef AuthTokens = Map<String, String?>;

enum Environment { uat, prod }

class ThemeConfig {
  const ThemeConfig({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final String primaryColor;
  final String secondaryColor;
}

class AuthChangeState {
  const AuthChangeState({
    required this.authenticated,
    required this.tokens,
  });

  final bool authenticated;
  final AuthTokens tokens;
}

class CheckoutPayload {
  const CheckoutPayload({
    required this.publicKey,
    required this.orderId,
    this.transactionId,
    required this.successUrl,
    required this.failureUrl,
  });

  final String publicKey;
  final String orderId;
  final String? transactionId;
  final String successUrl;
  final String failureUrl;

  factory CheckoutPayload.fromJson(Map<String, dynamic> json) {
    return CheckoutPayload(
      publicKey: json['publicKey'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      transactionId: json['transactionId'] as String?,
      successUrl: json['successUrl'] as String? ?? '',
      failureUrl: json['failureUrl'] as String? ?? '',
    );
  }
}

sealed class CheckoutEvent {
  const CheckoutEvent(this.payload);
  final CheckoutPayload payload;
}

class CheckoutRequested extends CheckoutEvent {
  const CheckoutRequested(super.payload);
}

class CheckoutSuccess extends CheckoutEvent {
  const CheckoutSuccess(super.payload);
}

class CheckoutFailure extends CheckoutEvent {
  const CheckoutFailure(super.payload);
}

class CheckoutTerminated extends CheckoutEvent {
  const CheckoutTerminated(super.payload);
}

class CheckoutConnectionError extends CheckoutEvent {
  const CheckoutConnectionError(super.payload, this.error);
  final Object error;
}

class CheckoutSdkError extends CheckoutEvent {
  const CheckoutSdkError(super.payload, this.errors);
  final Object errors;
}

abstract class StorageAdapter {
  Future<String?> getItem(String key);
  Future<void> setItem(String key, String value);
  Future<void> removeItem(String key);
}

abstract class Logger {
  void debug(Object? message, [List<Object?> args = const []]);
  void info(Object? message, [List<Object?> args = const []]);
  void warn(Object? message, [List<Object?> args = const []]);
  void error(Object? message, [List<Object?> args = const []]);
}

class WebViewMessage {
  const WebViewMessage({required this.type, this.payload});

  final String type;
  final Object? payload;
}

/// Shape injected into `window.__RN_WEBVIEW_CONFIG__`.
class WebViewInjectedConfig {
  const WebViewInjectedConfig({
    required this.firmId,
    required this.appName,
    required this.authFormSlug,
    required this.branchIdRi,
    this.branchIdNri,
    required this.helpUrl,
    required this.helpEmail,
    required this.tncUrl,
    required this.ppUrl,
    required this.disclaimerUrl,
    required this.aboutUrl,
    required this.appLogoUrl,
    required this.themePrimaryColor,
    required this.themeSecondaryColor,
    required this.environment,
    required this.sdkVersion,
  });

  final String firmId;
  final String appName;
  final String authFormSlug;
  final String branchIdRi;
  final String? branchIdNri;
  final String helpUrl;
  final String helpEmail;
  final String tncUrl;
  final String ppUrl;
  final String disclaimerUrl;
  final String aboutUrl;
  final String appLogoUrl;
  final String themePrimaryColor;
  final String themeSecondaryColor;
  final Environment environment;
  final String sdkVersion;

  Map<String, dynamic> toJson() => {
        'firmId': firmId,
        'appName': appName,
        'authFormSlug': authFormSlug,
        'branchIdRi': branchIdRi,
        if (branchIdNri != null) 'branchIdNri': branchIdNri,
        'helpUrl': helpUrl,
        'helpEmail': helpEmail,
        'tncUrl': tncUrl,
        'ppUrl': ppUrl,
        'disclaimerUrl': disclaimerUrl,
        'aboutUrl': aboutUrl,
        'appLogoUrl': appLogoUrl,
        'themePrimaryColor': themePrimaryColor,
        'themeSecondaryColor': themeSecondaryColor,
        'environment': environment.name,
        'sdkVersion': sdkVersion,
      };
}
