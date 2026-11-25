import 'package:bridge_flutter_sdk/bridge_flutter_sdk.dart';
import 'package:flutter/material.dart';

/// Pass session values at run time — never commit real JWTs:
/// ```
/// flutter run \
///   --dart-define=BRIDGE_ACCESS_TOKEN=... \
///   --dart-define=BRIDGE_REFRESH_TOKEN=... \
///   --dart-define=BRIDGE_ACCESS_EXPIRES_AT=... \
///   --dart-define=BRIDGE_REFRESH_EXPIRES_AT=... \
///   --dart-define=BRIDGE_CLIENT_NAME=NSEIXGA
/// ```
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BridgeSdkExampleApp());
}

class BridgeSdkExampleApp extends StatelessWidget {
  const BridgeSdkExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bridge-flutter-sdk',
      debugShowCheckedModeBanner: false,
      home: const _BridgeHome(),
    );
  }
}

class _BridgeHome extends StatefulWidget {
  const _BridgeHome();

  @override
  State<_BridgeHome> createState() => _BridgeHomeState();
}

class _BridgeHomeState extends State<_BridgeHome> {
  BridgeReturn? _returnResult;
  bool _showBridge = true;

  static const String _token = String.fromEnvironment(
    'BRIDGE_ACCESS_TOKEN',
    defaultValue: '',
  );
  static const String _refreshToken = String.fromEnvironment(
    'BRIDGE_REFRESH_TOKEN',
    defaultValue: '',
  );
  static const String _accessExpiresAt = String.fromEnvironment(
    'BRIDGE_ACCESS_EXPIRES_AT',
    defaultValue: '',
  );
  static const String _refreshExpiresAt = String.fromEnvironment(
    'BRIDGE_REFRESH_EXPIRES_AT',
    defaultValue: '',
  );
  static const String _clientName = String.fromEnvironment(
    'BRIDGE_CLIENT_NAME',
    defaultValue: '',
  );

  void _openBridge() {
    setState(() {
      _returnResult = null;
      _showBridge = true;
    });
  }

  bool get _hasSession =>
      _token.isNotEmpty &&
      _refreshToken.isNotEmpty &&
      _accessExpiresAt.isNotEmpty &&
      _refreshExpiresAt.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bridge example')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Pass BRIDGE_ACCESS_TOKEN, BRIDGE_REFRESH_TOKEN, '
              'BRIDGE_ACCESS_EXPIRES_AT, and BRIDGE_REFRESH_EXPIRES_AT '
              'via --dart-define. See example/README.md.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_showBridge) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bridge return')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'reason: ${_returnResult?.reason ?? '(none)'}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _returnResult?.url ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _openBridge,
                  child: const Text('Open Bridge again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: BridgeSdk(
        token: _token,
        clientName: _clientName,
        refreshToken: _refreshToken,
        accessTokenExpiresAt: _accessExpiresAt,
        refreshTokenExpiresAt: _refreshExpiresAt,
        returnUrl: 'bridgeflutter://sdk-return',
        environment: Environment.UAT,
        onReady: () => debugPrint('[SDK] ready'),
        onReturn: (result) {
          debugPrint(
            '[SDK] return reason=${result.reason} url=${result.url}',
          );
          setState(() {
            _returnResult = result;
            _showBridge = false;
          });
        },
        onError: (err) {
          debugPrint('[SDK] ${err.code.wireName} ${err.message}');
        },
        onDownloadSaved: (name) {
          debugPrint('[SDK] downloaded $name');
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('Saved $name')),
          );
        },
        onDownloadError: (err) {
          debugPrint('[SDK] download error $err');
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('Download failed: $err')),
          );
        },
      ),
    );
  }
}
