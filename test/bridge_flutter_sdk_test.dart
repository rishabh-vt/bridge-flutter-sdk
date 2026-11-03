import 'package:bridge_flutter_sdk/bridge_flutter_sdk.dart';
import 'package:bridge_flutter_sdk/src/internal/security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('security', () {
    test('blocks dangerous schemes', () {
      expect(isBlockedScheme('javascript:alert(1)'), isTrue);
      expect(isBlockedScheme('https://example.com'), isFalse);
    });

    test('builds origin whitelist from webview url', () {
      final set = buildOriginWhitelist(
        webviewUrl: 'https://trade-internal-staging.viewtrade.in/app',
        allowedOrigins: const ['https://assets.viewtrade.in'],
      );
      expect(set.contains('https://trade-internal-staging.viewtrade.in'), isTrue);
      expect(set.contains('https://assets.viewtrade.in'), isTrue);
    });

    test('safeJsLiteral escapes line/paragraph separators', () {
      final lit = safeJsLiteral('a\u2028b');
      expect(lit.contains('\\u2028'), isTrue);
    });

    test('validateUrlScheme requires https except dev', () {
      expect(validateUrlScheme('https://x.com').ok, isTrue);
      expect(validateUrlScheme('http://x.com').ok, isFalse);
      expect(validateUrlScheme('http://x.com', environment: 'dev').ok, isTrue);
    });
  });

  group('types', () {
    test('CheckoutPayload.fromJson', () {
      final p = CheckoutPayload.fromJson({
        'publicKey': 'test_pk',
        'orderId': 'order_1',
        'successUrl': 'https://ok',
        'failureUrl': 'https://fail',
      });
      expect(p.publicKey, 'test_pk');
      expect(p.orderId, 'order_1');
    });

    test('SdkError wire names', () {
      expect(SdkErrorCode.invalidConfig.wireName, 'INVALID_CONFIG');
      expect(
        SdkError(SdkErrorCode.webviewLoadFailed, 'boom').toString(),
        contains('WEBVIEW_LOAD_FAILED'),
      );
    });
  });
}
