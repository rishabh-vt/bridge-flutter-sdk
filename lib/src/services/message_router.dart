import 'dart:async';
import 'dart:convert';

import '../internal/constants.dart';
import '../types/types.dart';
import 'document_download.dart';
import 'storage_service.dart';

typedef TokensChangedCallback = void Function(AuthTokens tokens);
typedef LogoutCallback = void Function();
typedef CheckoutRequestedCallback = void Function(CheckoutPayload payload);
typedef WebViewReadyCallback = void Function();
typedef ClearWebViewAuthCallback = void Function();
typedef DocumentDownloadCompleteCallback = void Function(
  DocumentDownloadResult result,
);

class MessageRouter {
  MessageRouter({
    required this.storageService,
    required this.logger,
    this.onTokensChanged,
    this.onLogout,
    this.onCheckoutRequested,
    this.onWebViewReady,
    this.clearWebViewAuthState,
    this.onDocumentDownloadComplete,
  });

  final StorageService storageService;
  final Logger logger;
  final TokensChangedCallback? onTokensChanged;
  final LogoutCallback? onLogout;
  final CheckoutRequestedCallback? onCheckoutRequested;
  final WebViewReadyCallback? onWebViewReady;
  final ClearWebViewAuthCallback? clearWebViewAuthState;
  final DocumentDownloadCompleteCallback? onDocumentDownloadComplete;

  void handleRawMessage(String rawData) {
    late final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(rawData);
      if (decoded is! Map) {
        logger.warn('WebView message is not an object');
        return;
      }
      message = Map<String, dynamic>.from(decoded);
    } catch (error) {
      logger.warn('Failed to parse WebView message', [error]);
      return;
    }

    final type = message['type'];
    if (type is! String || type.isEmpty) return;

    if (type == 'debug.network') {
      final payload = message['payload'];
      if (payload is Map) {
        final phase = payload['phase'];
        final method = payload['method'];
        final url = payload['url'];
        final status = payload['status'];
        final durationMs = payload['durationMs'];
        final body = payload['body'];
        final error = payload['error'];
        if (phase == 'request') {
          logger.info('API → $method $url', [if (body != null) 'body=$body']);
        } else if (phase == 'response') {
          logger.info(
            'API ← $status $method $url (${durationMs}ms)',
            [if (body != null) 'body=$body'],
          );
        } else if (phase == 'error') {
          logger.warn('API ✕ $method $url', [error]);
        }
      }
      return;
    }

    logger.debug('Bridge ← $type', [message['payload']]);

    switch (type) {
      case 'auth.tokens-changed':
        onWebViewReady?.call();
        final tokens = _asAuthTokens(message['payload']);
        final hasActive = webviewAuthKeys.any((key) {
          final value = tokens[key];
          return value is String && value.trim().isNotEmpty;
        });
        if (!hasActive) {
          unawaited(storageService.clearTokens());
          onLogout?.call();
          clearWebViewAuthState?.call();
          return;
        }
        unawaited(storageService.saveTokens(tokens));
        onTokensChanged?.call(tokens);
        return;

      case 'auth.logout':
        unawaited(storageService.clearTokens());
        onLogout?.call();
        clearWebViewAuthState?.call();
        return;

      case 'request.auth-tokens':
      case 'web.app.mounted':
      case 'rn.webview.ready':
        onWebViewReady?.call();
        return;

      case 'funds.deposit.checkout':
        final payloadMap = message['payload'];
        if (payloadMap is Map) {
          onCheckoutRequested?.call(
            CheckoutPayload.fromJson(Map<String, dynamic>.from(payloadMap)),
          );
        }
        return;

      case 'document.open':
        final payload = message['payload'];
        if (payload is Map) {
          final url = payload['url'];
          final label = payload['label'];
          if (url is String && url.isNotEmpty) {
            final docLabel = label is String ? label : 'document';
            unawaited(() async {
              final ok = await documentDownloadService.downloadDocument(
                url,
                docLabel,
                logger,
              );
              onDocumentDownloadComplete?.call(
                DocumentDownloadResult(
                  total: 1,
                  succeeded: ok ? 1 : 0,
                  failed: ok ? 0 : 1,
                ),
              );
            }());
          }
        }
        return;

      case 'document.open-all':
        final payload = message['payload'];
        final documents = (payload is Map && payload['documents'] is List)
            ? (payload['documents'] as List)
            : const [];
        final downloads = <({String url, String label})>[];
        for (final doc in documents) {
          if (doc is! Map) continue;
          final url = doc['url'];
          final label = doc['label'];
          if (url is String && url.isNotEmpty) {
            downloads.add((
              url: url,
              label: label is String ? label : 'document',
            ));
          }
        }
        if (downloads.isEmpty) {
          logger.warn('document.open-all received no downloadable documents');
          return;
        }
        unawaited(() async {
          var succeeded = 0;
          for (final doc in downloads) {
            final ok = await documentDownloadService.downloadDocument(
              doc.url,
              doc.label,
              logger,
            );
            if (ok) succeeded += 1;
            await Future<void>.delayed(
              const Duration(milliseconds: AnimationTimings.openAllStaggerMs),
            );
          }
          onDocumentDownloadComplete?.call(
            DocumentDownloadResult(
              total: downloads.length,
              succeeded: succeeded,
              failed: downloads.length - succeeded,
            ),
          );
        }());
        return;

      case 'test.injected':
        logger.debug('Injection bridge OK');
        return;
    }
  }

  AuthTokens _asAuthTokens(Object? payload) {
    if (payload is! Map) return {};
    return payload.map(
      (k, v) => MapEntry(k.toString(), v as String?),
    );
  }
}
