# Changelog

## 2.1.5

- `returnUrl` is dynamic: hosts may pass a custom scheme or any HTTPS URL (still intercept + `onReturn`; plain `http` rejected).

## 2.1.4

- Widen `permission_handler` to `>=11.3.1 <13.0.0` so hosts on `^12` (e.g. macm_flutter) can resolve alongside the SDK.

## 2.1.3

- Android: detect system navigation bar via `viewPadding.bottom` and reserve space with a layout sibling + `ClipRect` so the Bridge tab bar is not drawn under the back/home bar (edge-to-edge / hybrid WebView).
- Soften Android safe-area JS so tab bar height is not collapsed when stripping double insets.

## 2.1.2

- Docs: README install constraint updated to `^2.1.1`.
- Release packaging aligned with funding, safe-area, and Android WebView fixes.

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
