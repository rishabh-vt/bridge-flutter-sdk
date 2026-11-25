# bridge-flutter-sdk example

Example host app for the **bridge-flutter-sdk** Flutter package (token → `/launch` → WebView).

Pass a UAT session via `--dart-define` — **do not commit real JWTs**.

```bash
cd example
flutter run \
  --dart-define=BRIDGE_ACCESS_TOKEN=your_access_token \
  --dart-define=BRIDGE_REFRESH_TOKEN=your_refresh_token \
  --dart-define=BRIDGE_ACCESS_EXPIRES_AT=1748430994 \
  --dart-define=BRIDGE_REFRESH_EXPIRES_AT=1749554194 \
  --dart-define=BRIDGE_CLIENT_NAME=NSEIXGA
```

Optional Android APK:

```bash
flutter build apk --debug \
  --dart-define=BRIDGE_ACCESS_TOKEN=your_access_token \
  --dart-define=BRIDGE_REFRESH_TOKEN=your_refresh_token \
  --dart-define=BRIDGE_ACCESS_EXPIRES_AT=1748430994 \
  --dart-define=BRIDGE_REFRESH_EXPIRES_AT=1749554194
```

The package import remains `package:bridge_flutter_sdk/...` (underscores); the project name is `bridge-flutter-sdk`.
