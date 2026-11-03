# bridge-flutter-sdk

Embeddable WebView-based onboarding and trading shell for Flutter host apps. Drop in one widget — the SDK handles authentication, session persistence, DigiLocker redirects, document downloads, and the GlomoPay checkout flow.

Independent Flutter port of `@viewtrade/bridge-react-native-sdk`, preserving the same web ↔ native message contract so the existing ViewTrade web app works unchanged.

> **Naming:** Project / repo = `bridge-flutter-sdk`. Dart package import name = `bridge_flutter_sdk` (underscores required by Dart).

---

## Requirements

- Flutter ≥ 3.24
- Dart ≥ 3.5
- iOS 13+ / Android 5.0+ (API 21+)

---

## Install

Published on [pub.dev](https://pub.dev/packages/bridge_flutter_sdk):

```yaml
dependencies:
  bridge_flutter_sdk: ^1.0.0
  # Transitive: glomopay_sdk, webview_flutter, shared_preferences, http, path_provider
```

```bash
flutter pub get
```

For local development against this repo:

```yaml
dependencies:
  bridge_flutter_sdk:
    path: ../bridge-flutter-sdk
```

### Android

Ensure `INTERNET` is present in `AndroidManifest.xml` (Flutter templates include it). For GlomoPay document uploads during checkout, also add camera/storage permissions as documented by [`glomopay_sdk`](https://pub.dev/packages/glomopay_sdk).

### iOS

For agreement PDF downloads to appear in the Files app, add to `Info.plist`:

```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

For GlomoPay camera/photo uploads, add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`.

---

## Quickstart

```dart
import 'package:bridge_flutter_sdk/bridge_flutter_sdk.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: BridgeSdk(
          firmId: 'YOUR_FIRM_ID',
          appName: 'Your App Name',
          authFormSlug: 'your-auth-form-slug',
          branchIdRi: 'YOUR_RI_BRANCH_ID',
          branchIdNri: 'YOUR_NRI_BRANCH_ID',
          helpEmail: 'support@yourdomain.com',
          helpUrl: 'https://www.yourdomain.com/help',
          tncUrl: 'https://www.yourdomain.com/terms',
          ppUrl: 'https://www.yourdomain.com/privacy',
          disclaimerUrl: 'https://www.yourdomain.com/disclaimer',
          aboutUrl: 'https://www.yourdomain.com/about',
          environment: Environment.uat,
          theme: const ThemeConfig(
            primaryColor: '#0F5D73',
            secondaryColor: '#E6F6FA',
          ),
        ),
      ),
    );
  }
}
```

---

## Imperative controller

```dart
final controller = ValueNotifier<BridgeSdkController?>(null);

BridgeSdk(
  controller: controller,
  // ...required props
);

controller.value?.reload();
await controller.value?.logout();
await controller.value?.postMessage({'type': 'host.ping'});
final auth = controller.value?.getAuthState();
```

| Method | Description |
|---|---|
| `reload()` | Reloads the WebView in place. |
| `logout()` | Clears stored tokens and in-page auth, then remounts the WebView. |
| `postMessage(message)` | Dispatches a `message` event into the WebView. |
| `getAuthState()` | Returns `{ authenticated, tokens }` from current SDK state. |

---

## SSO

```dart
BridgeSdk(
  // ...required props
  sso: true,
  userAccessToken: currentUserAccessToken,
)
```

The SDK does **not** refresh this token. When it expires, the host must supply a fresh `userAccessToken`.

---

## Callbacks

| Callback | When |
|---|---|
| `onReady` | Web app signals mounted/painted. |
| `onAuthChange` | Login/logout. |
| `onLogout` | Web app or `controller.logout()`. |
| `onCheckoutEvent` | GlomoPay lifecycle (`requested` / `success` / `failure` / `terminated` / `connection-error` / `sdk-error`). |
| `onError` | Config validation, WebView load/crash failures. |

---

## GlomoPay

Uses the official [`glomopay_sdk`](https://pub.dev/packages/glomopay_sdk) package. When the web app posts `funds.deposit.checkout`, the SDK overlays `GlomoPayCheckout` with the provided `publicKey` / `orderId`, then redirects the WebView to `successUrl` / `failureUrl`.

Mock/test mode is controlled by GlomoPay key prefixes (`test_…` / `mock_…`), not a hardcoded `devMode` flag.

---

## Web bridge compatibility

The Flutter SDK injects a shim so the existing web app keeps working:

```js
window.ReactNativeWebView.postMessage(...)
window.__RN_WEBVIEW_CONFIG__
```

Inbound messages arrive via a Flutter `JavascriptChannel` named `FlutterBridge`.

---

## Error codes

| Code | When |
|---|---|
| `INVALID_CONFIG` | Missing/empty required props, incomplete theme, SSO without token, rejected URL scheme. |
| `WEBVIEW_LOAD_FAILED` | Main-frame WebView load failure. |
| `WEBVIEW_RENDER_PROCESS_GONE` | Render process crash (auto-reload up to 2 times). |
| `STORAGE_FAILED` / `MESSAGE_PARSE_FAILED` / `CHECKOUT_FAILED` | Reserved. |

---

## Example

```bash
cd example
flutter run
```

---

## Versioning

Follows [Semantic Versioning](https://semver.org). See [CHANGELOG.md](./CHANGELOG.md).
