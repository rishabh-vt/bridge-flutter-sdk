# Changelog

## 2.1.1

- Android: keep funding/checkout navigations in the main WebView (avoid gesture→overlay).
- Funding `window.open` popups: full-bleed overlay with no host close button.
- Align iOS/Android bottom tab bar height (WKWebView safe-area + Android inset clamp).
- Android: WASM streaming fallback, hybrid composition, `textZoom: 100`.
- Do not treat arbitrary `data:` navigations as downloads.

## 2.1.0

Mobile App Integration (Bridge SDK UAT guide):

- Switch WebView to `flutter_inappwebview` (popups / `onCreateWindow`).
- `returnUrl` must be a **custom scheme** (e.g. `myapp://sdk-return`); `onReturn` receives `BridgeReturn` with `reason`.
- Camera/mic permission flow via `permission_handler`.
- Funding popup WebView, back-stack handling, `; wv` UA strip, third-party cookies.
- User-tapped links open in a closable overlay; document links view in-overlay.
- iOS `onNavigationResponse`: show MIME WK can render (PDF); download the rest.
- `mailto:` / `tel:` open the default system apps (`LaunchMode.externalApplication`).
- Document downloads: blob / zip / `download` attr + `onDownloadStartRequest`; MethodChannel `bridge_flutter_sdk/downloads`.
- Download permissions (Android storage/notifications; iOS Documents + Files sharing).
- Hide WebView scrollbars (native + CSS).
- Expiry fields required on launch payload.

## 2.0.0

Breaking rewrite around Bridge web SDK launch:

- `BridgeSdk` takes host tokens, `clientName`, `returnUrl`, and `environment`.
- On mount, SDK `POST`s `/launch` and loads `launchUrl` in a WebView.
- Removed firmId/theme/config injection, RN message shim, GlomoPay, etc.
