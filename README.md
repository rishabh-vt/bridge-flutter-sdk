# bridge-flutter-sdk

Flutter embedding of ViewTrade Bridge for mobile apps. Pass user tokens; the SDK `POST`s `/launch`, opens `launchUrl` in an InAppWebView, and intercepts a **custom-scheme** `returnUrl` when Bridge finishes.

Aligned with the Bridge **Mobile App Integration** module (`flutter_inappwebview`).

> **Naming:** Project / repo = `bridge-flutter-sdk`. Dart package import name = `bridge_flutter_sdk`.

---

## Requirements

- Flutter ≥ 3.24
- Dart ≥ 3.5
- iOS 15+ / Android 5.0+ (API 21+)

---

## Install

```bash
flutter pub add bridge_flutter_sdk
```

### Android (`AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>
```

### iOS (`Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for KYC / liveness verification.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required for KYC / liveness verification.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is required to upload documents.</string>
<!-- Register your returnUrl scheme, e.g. myapp://sdk-return -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>myapp</string></array>
  </dict>
</array>
```

---

## Quickstart

```dart
BridgeSdk(
  token: tokens.access_token,
  clientName: clientName,                 // assigned by Viewtrade
  refreshToken: tokens.refresh_token,
  accessTokenExpiresAt: '${tokens.access_expires_at}',
  refreshTokenExpiresAt: '${tokens.refresh_expires_at}',
  returnUrl: 'myapp://sdk-return',        // custom scheme — not https
  environment: Environment.UAT,           // or Environment.PROD
  onReturn: (result) {
    // result.reason: logout | email_verified | error | …
    // Close the Bridge screen / continue host flow.
  },
  onError: (err) => debugPrint(err.toString()),
)
```

### Launch flow (mobile)

1. Host obtains user tokens (partner login → impersonate) on **your server**.
2. SDK `POST`s tokens to Bridge `/launch` and receives `launchUrl`.
3. `launchUrl` loads in InAppWebView (camera/mic, file upload, funding popups supported).
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
| `environment` | yes | `UAT` or `PROD` |
| `accessTokenExpiresAt` | yes | Epoch seconds/ms |
| `refreshTokenExpiresAt` | yes | Epoch seconds/ms |
| `onReady` | no | First Bridge page finished |
| `onReturn` | no | Custom-scheme return intercepted (`BridgeReturn`) |
| `onError` | no | Config / launch / WebView failures |
| `controller` | no | `reload()` |

---

## Mobile behaviors (SDK)

- Custom-scheme `returnUrl` intercept (`reason` query forwarded)
- Funding `window.open` popup WebView
- Camera / mic `getUserMedia` via `permission_handler`
- `<input type="file">` handled by InAppWebView
- Strip `; wv` from Android user-agent (bank pages)
- Third-party cookies enabled
- Back: popup → Bridge history → leave screen
- `mailto:` / `tel:` opened externally via `url_launcher`
- Document downloads (blob ZIP + http PDFs) via `onDownloadStartRequest` + MethodChannel `bridge_flutter_sdk/downloads`
- Document **links** open in a closable overlay for viewing; **Download all** / zip / `download` attr save to disk
- Download permissions requested before save (Android storage / notifications; iOS Documents + Files sharing)

### Downloads (host setup)

Implement MethodChannel `bridge_flutter_sdk/downloads` → method `saveToDownloads` with `{ bytes, fileName, mimeType }` (see example `MainActivity.kt` / `AppDelegate.swift`).

| Platform | Permissions / setup |
|---|---|
| Android | `POST_NOTIFICATIONS` (API 33+); `WRITE_EXTERNAL_STORAGE` maxSdk 28; MediaStore Downloads on API 29+ |
| iOS | No runtime download permission — enable `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` so files appear in the Files app |

If the channel is missing, files fall back to app documents.

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
