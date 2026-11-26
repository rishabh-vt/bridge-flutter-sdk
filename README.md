# bridge-flutter-sdk

Client integration guide for **bridge_flutter_sdk** — embeddable Bridge onboarding / trading shell for Flutter hosts.

The SDK `POST`s host tokens to Bridge `/launch`, loads `launchUrl` in `flutter_inappwebview`, and intercepts a **custom-scheme** `returnUrl` when Bridge finishes.

> **Naming:** Project / repo = `bridge-flutter-sdk`. Dart import = `bridge_flutter_sdk`. Widget = `BridgeSdk`.

Aligned with the Bridge **Mobile App Integration** module (UAT guide). This replaces the older firmId / GlomoPay-prop client guide.

---

## Requirements

| Requirement | Version |
|---|---|
| Flutter | ≥ 3.24 |
| Dart | ≥ 3.5 |
| iOS | 15+ |
| Android | 5.0+ (API 21+) |

---

## Installation

```bash
flutter pub add bridge_flutter_sdk
```

Or in `pubspec.yaml`:

```yaml
dependencies:
  bridge_flutter_sdk: ^2.1.3
```

```dart
import 'package:bridge_flutter_sdk/bridge_flutter_sdk.dart';
```

### Android (`AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>

<!-- Allow url_launcher to resolve mail / phone apps -->
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW"/>
    <data android:scheme="mailto"/>
  </intent>
  <intent>
    <action android:name="android.intent.action.SENDTO"/>
    <data android:scheme="mailto"/>
  </intent>
  <intent>
    <action android:name="android.intent.action.DIAL"/>
    <data android:scheme="tel"/>
  </intent>
</queries>
```

Implement MethodChannel `bridge_flutter_sdk/downloads` → `saveToDownloads` (see example `MainActivity.kt`) so ZIP/PDF land in public Downloads.

### iOS (`Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for KYC / liveness verification.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required for KYC / liveness verification.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is required to upload documents.</string>
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>mailto</string>
  <string>tel</string>
</array>
<!-- Register your returnUrl scheme, e.g. myapp://sdk-return -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>myapp</string></array>
  </dict>
</array>
```

Implement MethodChannel `bridge_flutter_sdk/downloads` in `AppDelegate` (see example) so files appear under the app in Files.

---

## Quick start

Host obtains user tokens on **your server** (partner login → impersonate), then:

```dart
BridgeSdk(
  token: tokens.access_token,
  refreshToken: tokens.refresh_token,
  accessTokenExpiresAt: '${tokens.access_expires_at}',
  refreshTokenExpiresAt: '${tokens.refresh_expires_at}',
  clientName: clientName,              // assigned by Viewtrade
  returnUrl: 'myapp://sdk-return',     // custom scheme — not https
  environment: Environment.UAT,        // or Environment.PROD
  onReturn: (result) {
    // result.reason: logout | email_verified | error | …
    // Close the Bridge screen / continue host flow.
  },
  onError: (err) => debugPrint(err.toString()),
)
```

### Launch flow

1. Host obtains `tokens` (never expose partner API keys to the device).
2. SDK `POST`s JSON to Bridge `/launch` and receives `launchUrl`.
3. `launchUrl` loads in InAppWebView (camera/mic, file upload, funding popups).
4. On completion Bridge navigates to `returnUrl?reason=…` — SDK **cancels** the load and fires `onReturn`.

| `environment` | Launch URL |
|---|---|
| `Environment.UAT` | `https://bridge-backend-staging.viewtrade.in/launch` |
| `Environment.PROD` | `https://sdk-backend.viewtrade.in/launch` |

---

## Props

| Prop | Required | Description |
|---|---|---|
| `token` | yes | `tokens.access_token` |
| `refreshToken` | yes | `tokens.refresh_token` |
| `clientName` | yes | Partner client id from Viewtrade |
| `returnUrl` | yes | Custom scheme, e.g. `myapp://sdk-return` |
| `environment` | yes | `Environment.UAT` or `Environment.PROD` |
| `accessTokenExpiresAt` | yes | Epoch seconds/ms |
| `refreshTokenExpiresAt` | yes | Epoch seconds/ms |
| `onReady` | no | First Bridge page finished |
| `onReturn` | no | Custom-scheme return (`BridgeReturn`) |
| `onError` | no | Config / launch / WebView failures |
| `onDownloadSaved` | no | File name after a successful download |
| `onDownloadError` | no | Download failure |
| `controller` | no | `reload()` |

---

## Mobile behaviors (SDK)

- Custom-scheme `returnUrl` intercept (`reason` forwarded)
- Funding `window.open` / user links → closable overlay WebView
- Document **links** open for viewing; **Download all** / zip / `download` attr save to disk
- PDFs WK can render are shown; MIME types it cannot show are downloaded
- Camera / mic via `permission_handler`
- `<input type="file">` via InAppWebView
- Strip `; wv` from Android user-agent (bank pages)
- Third-party cookies enabled; WebView scrollbars hidden
- Back: overlay → Bridge history → leave screen
- `mailto:` / `tel:` → default system apps (`LaunchMode.externalApplication`)

---

## Error codes

| Code | When |
|---|---|
| `INVALID_CONFIG` | Missing props or http(s) `returnUrl` |
| `LAUNCH_FAILED` | `/launch` network / HTTP / missing `launchUrl` |
| `WEBVIEW_LOAD_FAILED` | Main-frame load failure |

---

## Versioning

Follows [Semantic Versioning](https://semver.org). See [CHANGELOG.md](./CHANGELOG.md).
