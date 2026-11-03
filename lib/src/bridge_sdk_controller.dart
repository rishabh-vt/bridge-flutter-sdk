import 'types/types.dart';

/// Imperative API mirroring the React Native `BridgeSDKRef`.
abstract class BridgeSdkController {
  void reload();
  Future<void> logout();
  Future<void> postMessage(Object? message);
  AuthChangeState getAuthState();
}
