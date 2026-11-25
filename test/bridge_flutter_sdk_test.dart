import 'dart:convert';

import 'package:bridge_flutter_sdk/bridge_flutter_sdk.dart';
import 'package:bridge_flutter_sdk/src/internal/security.dart';
import 'package:bridge_flutter_sdk/src/services/download_service.dart';
import 'package:bridge_flutter_sdk/src/services/launch_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Environment', () {
    test('UAT and PROD map to the correct launch URLs', () {
      expect(
        Environment.UAT.launchUrl,
        'https://bridge-backend-staging.viewtrade.in/launch',
      );
      expect(
        Environment.PROD.launchUrl,
        'https://sdk-backend.viewtrade.in/launch',
      );
    });
  });

  group('security', () {
    test('blocks dangerous schemes', () {
      expect(isBlockedScheme('javascript:alert(1)'), isTrue);
      expect(isBlockedScheme('https://example.com'), isFalse);
    });

    test('validateHttpsUrl requires https', () {
      expect(validateHttpsUrl('https://x.com').ok, isTrue);
      expect(validateHttpsUrl('http://x.com').ok, isFalse);
    });

    test('validateReturnUrl requires custom scheme', () {
      expect(validateReturnUrl('myapp://sdk-return').ok, isTrue);
      expect(validateReturnUrl('bridgeflutter://sdk-return').ok, isTrue);
      expect(validateReturnUrl('https://yourapp.com/return').ok, isFalse);
      expect(validateReturnUrl('http://yourapp.com/return').ok, isFalse);
    });

    test('isReturnUrl matches custom scheme + host', () {
      const ret = 'myapp://sdk-return';
      expect(isReturnUrl(ret, ret), isTrue);
      expect(isReturnUrl('$ret?reason=logout', ret), isTrue);
      expect(isReturnUrl('$ret?reason=email_verified', ret), isTrue);
      expect(isReturnUrl('myapp://other', ret), isFalse);
      expect(isReturnUrl('https://yourapp.com/return', ret), isFalse);
    });

    test('returnReason reads query param', () {
      expect(
        returnReason('myapp://sdk-return?reason=logout'),
        'logout',
      );
      expect(returnReason('myapp://sdk-return'), isNull);
    });
  });

  group('LaunchRequest', () {
    test('toJson includes all launch fields', () {
      final body = LaunchRequest(
        token: 'a',
        refreshToken: 'r',
        clientName: 'MAPS',
        returnUrl: 'myapp://sdk-return',
        accessTokenExpiresAt: '1748430994',
        refreshTokenExpiresAt: '1749554194',
      ).toJson();

      expect(body, {
        'token': 'a',
        'clientName': 'MAPS',
        'refreshToken': 'r',
        'returnUrl': 'myapp://sdk-return',
        'accessTokenExpiresAt': '1748430994',
        'refreshTokenExpiresAt': '1749554194',
      });
    });
  });

  group('LaunchService', () {
    const request = LaunchRequest(
      token: 'access',
      refreshToken: 'refresh',
      clientName: 'MAPS',
      returnUrl: 'myapp://sdk-return',
      accessTokenExpiresAt: '1748430994',
      refreshTokenExpiresAt: '1749554194',
    );

    test('POSTs to UAT launch URL and returns launchUrl', () async {
      late Uri calledUri;
      final client = MockClient((http.Request req) async {
        calledUri = req.url;
        expect(req.method, 'POST');
        return http.Response(
          jsonEncode({'launchUrl': 'https://bridge.example/session/abc'}),
          200,
        );
      });

      final service = LaunchService(client: client);
      final url = await service.fetchLaunchUrl(
        environment: Environment.UAT,
        request: request,
      );
      expect(calledUri.toString(), Environment.UAT.launchUrl);
      expect(url, 'https://bridge.example/session/abc');
      service.close();
    });

    test('throws LAUNCH_FAILED on non-2xx', () async {
      final client = MockClient(
        (_) async => http.Response('unauthorized', 401),
      );
      final service = LaunchService(client: client);
      expect(
        () => service.fetchLaunchUrl(
          environment: Environment.UAT,
          request: request,
        ),
        throwsA(
          isA<SdkError>().having(
            (e) => e.code,
            'code',
            SdkErrorCode.launchFailed,
          ),
        ),
      );
      service.close();
    });
  });

  group('BridgeSdk validation', () {
    testWidgets('rejects https returnUrl (must be custom scheme)',
        (tester) async {
      SdkError? seen;
      await tester.pumpWidget(
        MaterialApp(
          home: BridgeSdk(
            token: 't',
            refreshToken: 'r',
            clientName: 'MAPS',
            returnUrl: 'https://yourapp.com/bridge-return',
            accessTokenExpiresAt: '1',
            refreshTokenExpiresAt: '2',
            environment: Environment.UAT,
            onError: (e) => seen = e,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(seen, isNotNull);
      expect(seen!.code, SdkErrorCode.invalidConfig);
      expect(seen!.message, contains('returnUrl'));
    });

    testWidgets('reports INVALID_CONFIG when token is empty', (tester) async {
      SdkError? seen;
      await tester.pumpWidget(
        MaterialApp(
          home: BridgeSdk(
            token: '',
            refreshToken: 'r',
            clientName: 'MAPS',
            returnUrl: 'myapp://sdk-return',
            accessTokenExpiresAt: '1',
            refreshTokenExpiresAt: '2',
            environment: Environment.UAT,
            onError: (e) => seen = e,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(seen, isNotNull);
      expect(seen!.code, SdkErrorCode.invalidConfig);
      expect(seen!.message, contains('token'));
    });
  });

  group('downloads', () {
    test('isDownloadableUrl detects document extensions', () {
      expect(
        isDownloadableUrl(WebUri('https://x.com/a/report.pdf')),
        isTrue,
      );
      expect(
        isDownloadableUrl(WebUri('https://x.com/a/archive.zip')),
        isTrue,
      );
      expect(
        isDownloadableUrl(WebUri('https://x.com/a/report.pdf?token=1')),
        isTrue,
      );
      expect(
        isDownloadableUrl(WebUri('https://x.com/app')),
        isFalse,
      );
    });

    test('isDownloadableMime detects PDF and office types', () {
      expect(isDownloadableMime('application/pdf'), isTrue);
      expect(isDownloadableMime('application/pdf; charset=binary'), isTrue);
      expect(isDownloadableMime('application/zip'), isTrue);
      expect(isDownloadableMime('text/html'), isFalse);
    });

    test('shouldSaveDocument combines URL and MIME', () {
      expect(
        shouldSaveDocument(url: 'https://x.com/a.pdf'),
        isTrue,
      );
      expect(
        shouldSaveDocument(
          url: 'https://x.com/download',
          mimeType: 'application/pdf',
        ),
        isTrue,
      );
      expect(
        shouldSaveDocument(url: 'https://x.com/app', mimeType: 'text/html'),
        isFalse,
      );
    });

    test('shouldForceDownload only for archives, not viewable PDFs', () {
      expect(shouldForceDownload(url: 'https://x.com/a.pdf'), isFalse);
      expect(shouldForceDownload(url: 'https://x.com/all.zip'), isTrue);
      expect(
        shouldForceDownload(mimeType: 'application/zip'),
        isTrue,
      );
      expect(
        shouldForceDownload(mimeType: 'application/pdf'),
        isFalse,
      );
      expect(
        shouldForceDownload(
          url: 'https://x.com/export',
          suggestedFileName: 'documents.zip',
        ),
        isTrue,
      );
    });

    test('sanitizeFileName strips illegal characters', () {
      expect(sanitizeFileName('a/b:c*.pdf'), 'a_b_c_.pdf');
    });
  });

  group('errors', () {
    test('SdkError wire names', () {
      expect(SdkErrorCode.invalidConfig.wireName, 'INVALID_CONFIG');
      expect(SdkErrorCode.launchFailed.wireName, 'LAUNCH_FAILED');
      expect(
        SdkError(SdkErrorCode.webviewLoadFailed, 'boom').toString(),
        contains('WEBVIEW_LOAD_FAILED'),
      );
    });
  });
}
