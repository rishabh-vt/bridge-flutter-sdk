// SDK-internal constants. Tenant config is supplied at runtime via BridgeSdk props.

const String sdkVersion = '1.0.0';
const Map<String, String> webviewUrls = {
  'uat': 'https://trade-internal-staging.viewtrade.in/',
  'prod': 'https://trade-internal-sdk.viewtrade.in/',
};

/// Origins always permitted — ViewTrade assets + DigiLocker OAuth.
const List<String> sdkDefaultAllowedOrigins = [
  'https://assets.viewtrade.in',
  'https://digilocker.meripehchaan.gov.in',
  'https://consent.digilocker.gov.in',
  'https://digilocker.wayne-rta.com',
];

const String webviewTokensKey = 'webview_auth_tokens';

const List<String> webviewAuthKeys = [
  'accessToken',
  'refreshToken',
  'watchmanToken',
  'ssoToken',
  'middlewareToken',
];

const Set<String> webviewAuthKeysSet = {
  'accessToken',
  'refreshToken',
  'watchmanToken',
  'ssoToken',
  'middlewareToken',
};

class AnimationTimings {
  static const int loaderFadeDurationMs = 200;
  static const int checkoutStartDelayMs = 300;
  static const int webviewPaintGraceMs = 600;
  static const int openAllStaggerMs = 350;
  static const int loadEndFallbackMs = 1500;
  static const int maxOverlayMs = 2500;
}
