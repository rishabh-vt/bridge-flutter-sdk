# Changelog

## 1.0.0

- Initial Flutter release mirroring `@viewtrade/bridge-react-native-sdk`.
- WebView shell with `__RN_WEBVIEW_CONFIG__` injection and `ReactNativeWebView` postMessage shim.
- Auth token persistence via `shared_preferences` (pluggable `StorageAdapter`).
- DigiLocker / assets origin whitelist and scheme blocklist.
- Document download (`document.open` / `document.open-all`).
- GlomoPay checkout via [`glomopay_sdk`](https://pub.dev/packages/glomopay_sdk).
- Imperative controller: `reload`, `logout`, `postMessage`, `getAuthState`.
- SSO seeding via `sso` + `userAccessToken`.
