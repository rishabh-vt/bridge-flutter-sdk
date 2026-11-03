import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glomopay_sdk/glomopay_sdk.dart' hide SdkError;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'bridge_sdk_controller.dart';
import 'internal/constants.dart';
import 'internal/default_adapters.dart';
import 'internal/security.dart';
import 'services/document_download.dart';
import 'services/message_router.dart';
import 'services/storage_service.dart';
import 'services/webview_bridge.dart';
import 'types/errors.dart';
import 'types/types.dart';

/// Embeddable WebView-based onboarding/trading shell for Flutter host apps.
class BridgeSdk extends StatefulWidget {
  const BridgeSdk({
    super.key,
    required this.firmId,
    required this.appName,
    required this.authFormSlug,
    required this.branchIdRi,
    required this.branchIdNri,
    required this.helpUrl,
    required this.helpEmail,
    required this.tncUrl,
    required this.ppUrl,
    required this.disclaimerUrl,
    required this.aboutUrl,
    required this.environment,
    required this.theme,
    this.webviewUrl,
    this.appLogoUrl,
    this.storage,
    this.logger,
    this.allowedOrigins,
    this.sso = false,
    this.userAccessToken,
    this.onReady,
    this.onAuthChange,
    this.onLogout,
    this.onCheckoutEvent,
    this.onError,
    this.controller,
    this.enableApiLogs = false,
  });

  final String firmId;
  final String appName;
  final String authFormSlug;
  final String branchIdRi;
  final String branchIdNri;
  final String helpUrl;
  final String helpEmail;
  final String tncUrl;
  final String ppUrl;
  final String disclaimerUrl;
  final String aboutUrl;
  final Environment environment;
  final ThemeConfig theme;

  final String? webviewUrl;
  final String? appLogoUrl;
  final StorageAdapter? storage;
  final Logger? logger;
  final List<String>? allowedOrigins;

  final bool sso;
  final String? userAccessToken;

  final VoidCallback? onReady;
  final ValueChanged<AuthChangeState>? onAuthChange;
  final VoidCallback? onLogout;
  final ValueChanged<CheckoutEvent>? onCheckoutEvent;
  final ValueChanged<SdkError>? onError;

  /// Optional host-owned controller for imperative API access.
  final ValueNotifier<BridgeSdkController?>? controller;

  /// When true, intercepts WebView `fetch`/XHR and prints request/response
  /// logs to the Flutter console (truncated bodies). Debug/dev only.
  final bool enableApiLogs;

  @override
  State<BridgeSdk> createState() => _BridgeSdkState();
}

class _BridgeSdkState extends State<BridgeSdk> implements BridgeSdkController {
  late final Logger _logger;
  late final StorageAdapter _storageAdapter;
  late final StorageService _storageService;
  late final MessageRouter _messageRouter;

  WebViewController? _webViewController;
  AuthTokens _storedTokens = {};
  int _webViewInstanceKey = 0;
  bool _authHydrated = false;
  bool _canGoBack = false;
  bool _hasEverBeenReady = false;
  bool _bridgeNavigationInProgress = false;

  CheckoutPayload? _checkout;

  Timer? _readyFallbackTimer;
  Timer? _readySignalTimer;
  Timer? _maxOverlayTimer;

  String get _resolvedWebviewUrl {
    final override = widget.webviewUrl;
    if (override != null && override.isNotEmpty) return override;
    return webviewUrls[widget.environment.name] ?? webviewUrls['uat']!;
  }

  @override
  void initState() {
    super.initState();
    _logger = widget.logger ??
        createDefaultLogger(enabled: !kReleaseMode);
    _storageAdapter = widget.storage ?? getDefaultStorage();
    _storageService = StorageService(_storageAdapter, _logger);

    _messageRouter = MessageRouter(
      storageService: _storageService,
      logger: _logger,
      onTokensChanged: _handleTokensChanged,
      onLogout: _handleLogout,
      onCheckoutRequested: _handleCheckoutRequested,
      onWebViewReady: _handleWebViewReady,
      clearWebViewAuthState: _clearWebViewAuthState,
      onDocumentDownloadComplete: _handleDocumentDownloadComplete,
    );

    widget.controller?.value = this;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _validateAndBootstrap();
    });
  }

  @override
  void didUpdateWidget(covariant BridgeSdk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.value = null;
      widget.controller?.value = this;
    }
  }

  @override
  void dispose() {
    widget.controller?.value = null;
    _readyFallbackTimer?.cancel();
    _readySignalTimer?.cancel();
    _maxOverlayTimer?.cancel();
    super.dispose();
  }

  Future<void> _validateAndBootstrap() async {
    final err = _validateProps(_resolvedWebviewUrl);
    if (err != null) {
      _logger.error(err.message);
      widget.onError?.call(err);
    }

    if (widget.sso && widget.userAccessToken != null) {
      _storedTokens = {
        'accessToken': widget.userAccessToken,
        'refreshToken': null,
      };
      await _storageService.saveTokens(_storedTokens);
    } else {
      _storedTokens = await _storageService.loadTokens();
    }

    if (!mounted) return;
    setState(() {
      _authHydrated = true;
    });
    await _createWebViewController();
  }

  SdkError? _validateProps(String resolvedUrl) {
    final required = <String, String>{
      'firmId': widget.firmId,
      'appName': widget.appName,
      'authFormSlug': widget.authFormSlug,
      'branchIdRi': widget.branchIdRi,
      'branchIdNri': widget.branchIdNri,
      'helpUrl': widget.helpUrl,
      'helpEmail': widget.helpEmail,
      'tncUrl': widget.tncUrl,
      'ppUrl': widget.ppUrl,
      'disclaimerUrl': widget.disclaimerUrl,
      'aboutUrl': widget.aboutUrl,
    };
    for (final entry in required.entries) {
      if (entry.value.isEmpty) {
        return SdkError(
          SdkErrorCode.invalidConfig,
          'BridgeSDK: required prop "${entry.key}" must be a non-empty string',
        );
      }
    }
    if (widget.theme.primaryColor.isEmpty ||
        widget.theme.secondaryColor.isEmpty) {
      return SdkError(
        SdkErrorCode.invalidConfig,
        'BridgeSDK: required prop "theme" must have primaryColor and secondaryColor',
      );
    }
    if (widget.sso &&
        (widget.userAccessToken == null || widget.userAccessToken!.isEmpty)) {
      return SdkError(
        SdkErrorCode.invalidConfig,
        'BridgeSDK: userAccessToken is required when sso is true',
      );
    }
    final schemeCheck = validateUrlScheme(
      resolvedUrl,
      environment: widget.environment.name,
    );
    if (!schemeCheck.ok) {
      return SdkError(
        SdkErrorCode.invalidConfig,
        'BridgeSDK: webviewUrl rejected — ${schemeCheck.reason}',
      );
    }
    return null;
  }

  WebViewInjectedConfig _buildInjectedConfig() {
    return WebViewInjectedConfig(
      firmId: widget.firmId,
      appName: widget.appName,
      authFormSlug: widget.authFormSlug,
      sdkVersion: sdkVersion,
      branchIdRi: widget.branchIdRi,
      branchIdNri: widget.branchIdNri,
      helpUrl: widget.helpUrl,
      helpEmail: widget.helpEmail,
      tncUrl: widget.tncUrl,
      ppUrl: widget.ppUrl,
      disclaimerUrl: widget.disclaimerUrl,
      aboutUrl: widget.aboutUrl,
      appLogoUrl: widget.appLogoUrl ?? '',
      environment: widget.environment,
      themePrimaryColor: widget.theme.primaryColor,
      themeSecondaryColor: widget.theme.secondaryColor,
    );
  }

  Set<String> get _allowedOrigins {
    return buildOriginWhitelist(
      webviewUrl: _resolvedWebviewUrl,
      allowedOrigins: [
        ...sdkDefaultAllowedOrigins,
        ...?widget.allowedOrigins,
      ],
    );
  }

  String? _originOf(String url) => safeOrigin(url);

  bool _isBridgeNavigation(String? url) {
    final webviewOrigin = _originOf(_resolvedWebviewUrl);
    if (url == null || webviewOrigin == null) return true;
    return _originOf(url) == webviewOrigin;
  }

  Future<void> _createWebViewController() async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: false,
        mediaTypesRequiringUserAction: const {
          PlaybackMediaTypes.audio,
          PlaybackMediaTypes.video,
        },
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(
      _parseColor(widget.theme.secondaryColor),
    );
    await controller.addJavaScriptChannel(
      WebViewBridge.flutterChannelName,
      onMessageReceived: (message) {
        _messageRouter.handleRawMessage(message.message);
      },
    );

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (widget.enableApiLogs) {
            _logger.debug('Nav → ${request.url}');
          }
          final decision = isUrlAllowed(request.url, _allowedOrigins);
          if (!decision.allowed) {
            _logger.warn(
              'WebView navigation blocked',
              [decision.reason, request.url],
            );
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) async {
          // Inject bridge shim + config as early as possible.
          await _injectBootstrap();

          if (!_isBridgeNavigation(url)) return;
          if (_hasEverBeenReady) return;

          _bridgeNavigationInProgress = true;
          _maxOverlayTimer?.cancel();
          _maxOverlayTimer = Timer(
            const Duration(milliseconds: AnimationTimings.maxOverlayMs),
            () {
              _bridgeNavigationInProgress = false;
            },
          );
        },
        onPageFinished: (url) async {
          // Re-inject after load so SPA boots always see config + shim.
          await _injectBootstrap();

          if (!_bridgeNavigationInProgress) return;
          _bridgeNavigationInProgress = false;
          _maxOverlayTimer?.cancel();

          if (_readySignalTimer != null) return;
          _readyFallbackTimer?.cancel();
          _readyFallbackTimer = Timer(
            const Duration(milliseconds: AnimationTimings.loadEndFallbackMs),
            () {},
          );
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? true) {
            widget.onError?.call(
              SdkError(
                SdkErrorCode.webviewLoadFailed,
                error.description,
                error,
              ),
            );
          }
        },
        onUrlChange: (change) async {
          final canGoBack = await _webViewController?.canGoBack() ?? false;
          if (mounted) {
            setState(() => _canGoBack = canGoBack);
          }
        },
      ),
    );

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      await android.setMediaPlaybackRequiresUserGesture(true);
      await AndroidWebViewController.enableDebugging(!kReleaseMode);
      await android.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (_) async {
          return const GeolocationPermissionsResponse(
            allow: false,
            retain: false,
          );
        },
      );
    }

    if (controller.platform is WebKitWebViewController) {
      final ios = controller.platform as WebKitWebViewController;
      await ios.setAllowsBackForwardNavigationGestures(true);
    }

    await controller.setUserAgent(await _buildUserAgent(controller));
    await controller.loadRequest(Uri.parse(_resolvedWebviewUrl));

    if (!mounted) return;
    setState(() {
      _webViewController = controller;
    });
  }

  Future<String> _buildUserAgent(WebViewController controller) async {
    // Append BridgeSDK/<version> for backend identification.
    try {
      final current = await controller
          .runJavaScriptReturningResult('navigator.userAgent');
      final ua = current.toString().replaceAll('"', '');
      if (ua.contains('BridgeSDK/')) return ua;
      return '$ua BridgeSDK/$sdkVersion';
    } catch (_) {
      return 'BridgeSDK/$sdkVersion';
    }
  }

  Future<void> _injectBootstrap() async {
    final controller = _webViewController;
    if (controller == null) return;
    final script = webViewBridge.getInjectionScript(
      _storedTokens,
      _buildInjectedConfig(),
      enableApiLogs: widget.enableApiLogs,
    );
    try {
      await controller.runJavaScript(script);
    } catch (error) {
      _logger.warn('Failed to inject WebView bootstrap', [error]);
    }
  }

  Future<void> _runScript(String script) async {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      await controller.runJavaScript(script);
    } catch (error) {
      _logger.warn('Failed to run WebView script', [error]);
    }
  }

  void _handleTokensChanged(AuthTokens tokens) {
    setState(() => _storedTokens = tokens);
    widget.onAuthChange?.call(
      AuthChangeState(authenticated: true, tokens: tokens),
    );
  }

  void _handleLogout() {
    _resetWebView();
    widget.onAuthChange?.call(
      const AuthChangeState(authenticated: false, tokens: {}),
    );
    widget.onLogout?.call();
  }

  void _handleCheckoutRequested(CheckoutPayload payload) {
    setState(() => _checkout = payload);
    widget.onCheckoutEvent?.call(CheckoutRequested(payload));
  }

  void _handleWebViewReady() {
    _maxOverlayTimer?.cancel();
    _readyFallbackTimer?.cancel();
    _readySignalTimer?.cancel();
    _readySignalTimer = Timer(
      const Duration(milliseconds: AnimationTimings.webviewPaintGraceMs),
      () {
        _hasEverBeenReady = true;
        widget.onReady?.call();
      },
    );
  }

  void _handleDocumentDownloadComplete(DocumentDownloadResult result) {
    unawaited(
      _runScript(
        webViewBridge.getPostMessageScript({
          'type': 'document.download-complete',
          'payload': result.toJson(),
        }),
      ),
    );
  }

  void _clearWebViewAuthState() {
    unawaited(_runScript(webViewBridge.getClearAuthScript()));
  }

  Future<void> _resetWebView() async {
    _hasEverBeenReady = false;
    setState(() {
      _storedTokens = {};
      _webViewInstanceKey += 1;
      _webViewController = null;
    });
    await _createWebViewController();
  }

  Future<void> _goToUrl(String url) async {
    await _runScript(webViewBridge.getLocationScript(url));
  }

  void _finishCheckout(CheckoutEvent event, {String? navigateUrl}) {
    widget.onCheckoutEvent?.call(event);
    if (navigateUrl != null && navigateUrl.isNotEmpty) {
      unawaited(_goToUrl(navigateUrl));
    }
    if (mounted) setState(() => _checkout = null);
  }

  Color _parseColor(String hex) {
    var cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return Colors.white;
    return Color(value);
  }

  // ─── BridgeSdkController ───────────────────────────────────────────────────

  @override
  void reload() {
    unawaited(_webViewController?.reload());
  }

  @override
  Future<void> logout() async {
    await _storageService.clearTokens();
    _clearWebViewAuthState();
    await _resetWebView();
  }

  @override
  Future<void> postMessage(Object? message) async {
    await _runScript(webViewBridge.getPostMessageScript(message));
  }

  @override
  AuthChangeState getAuthState() {
    final authenticated = _storedTokens.values.any(
      (v) => v is String && v.isNotEmpty,
    );
    return AuthChangeState(
      authenticated: authenticated,
      tokens: Map<String, String?>.from(_storedTokens),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarBg = _parseColor(widget.theme.secondaryColor);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: ColoredBox(
        color: statusBarBg,
        child: SafeArea(
          top: false,
          bottom: false,
          child: PopScope(
            canPop: !_canGoBack,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              if (_canGoBack) {
                await _webViewController?.goBack();
              }
            },
            child: Stack(
              children: [
                if (_authHydrated && _webViewController != null)
                  KeyedSubtree(
                    key: ValueKey(_webViewInstanceKey),
                    child: WebViewWidget(controller: _webViewController!),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                if (_checkout != null) _buildCheckoutOverlay(_checkout!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutOverlay(CheckoutPayload checkout) {
    return Positioned.fill(
      child: Material(
        color: Colors.white,
        child: GlomoPayCheckout(
          config: GlomoPayConfig(
            publicKey: checkout.publicKey,
            orderId: checkout.orderId,
          ),
          onPaymentSuccess: (_) {
            _finishCheckout(
              CheckoutSuccess(checkout),
              navigateUrl: checkout.successUrl,
            );
          },
          onPaymentFailure: (_) {
            _finishCheckout(
              CheckoutFailure(checkout),
              navigateUrl: checkout.failureUrl,
            );
          },
          onUserJourneyCompleted: (_) {
            // Async bank-transfer path — treat as success redirect for web parity.
            _finishCheckout(
              CheckoutSuccess(checkout),
              navigateUrl: checkout.successUrl,
            );
          },
          onSdkError: (errors) {
            _finishCheckout(CheckoutSdkError(checkout, errors));
          },
          onConnectionError: (error) {
            _finishCheckout(
              CheckoutConnectionError(checkout, error),
              navigateUrl: checkout.failureUrl,
            );
          },
          onPaymentTerminate: (_) {
            _finishCheckout(
              CheckoutTerminated(checkout),
              navigateUrl: checkout.failureUrl,
            );
          },
        ),
      ),
    );
  }
}
