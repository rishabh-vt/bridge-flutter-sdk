import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import 'bridge_sdk_controller.dart';
import 'internal/security.dart';
import 'services/download_service.dart';
import 'services/launch_service.dart';
import 'types/errors.dart';
import 'types/types.dart';

const String _sdkVersion = '2.1.4';

/// Capture blob: URLs and route ZIP / `download` attr clicks to Flutter.
/// Handles programmatic `a.click()` used by "Download all documents".
const String _blobCaptureJs = r'''
(function () {
  if (window.__blobCapture) return;
  window.__blobCapture = true;
  window.__blobs = {}; window.__blobNames = {};

  function isArchive(href, name) {
    return /\.zip(\?|#|$)/i.test(href || '') || /\.zip$/i.test(name || '');
  }
  function shouldSave(a) {
    if (!a || !a.href) return false;
    var href = a.href;
    var name = a.getAttribute('download') || a.download || '';
    // Explicit download / blob / zip → save. Plain PDF hrefs stay viewable.
    return !!(name || href.indexOf('blob:') === 0 || isArchive(href, name));
  }
  function remember(a) {
    try {
      if (a && a.href && a.href.indexOf('blob:') === 0) {
        var n = a.getAttribute('download') || a.download || '';
        if (n) window.__blobNames[a.href] = n;
      }
    } catch (e) {}
  }
  function handoff(a) {
    try {
      remember(a);
      if (!shouldSave(a)) return false;
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler(
          'bridgeDownload',
          a.href,
          a.getAttribute('download') || a.download || ''
        );
        return true;
      }
    } catch (e) {}
    return false;
  }

  var create = URL.createObjectURL;
  URL.createObjectURL = function (obj) {
    var url = create.call(URL, obj);
    try {
      if (obj instanceof Blob) {
        window.__blobs[url] = obj;
        // Prefer zip filename when Bridge builds a bulk archive blob.
        if (obj.type && /zip/i.test(obj.type)) {
          window.__blobNames[url] = window.__blobNames[url] || 'documents.zip';
        }
      }
    } catch (e) {}
    return url;
  };

  var click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (handoff(this)) return;
    return click.apply(this, arguments);
  };
  var dispatch = HTMLAnchorElement.prototype.dispatchEvent;
  HTMLAnchorElement.prototype.dispatchEvent = function (evt) {
    if (evt && evt.type === 'click' && handoff(this)) {
      if (typeof evt.preventDefault === 'function') evt.preventDefault();
      return false;
    }
    return dispatch.apply(this, arguments);
  };
})();
''';

/// DOM click fallback for downloads + mailto/tel (opens default system apps).
const String _downloadClickJs = r'''
(function () {
  if (window.__bridgeDownloadClick) return;
  window.__bridgeDownloadClick = true;
  function isArchive(href, name) {
    return /\.zip(\?|#|$)/i.test(href || '') || /\.zip$/i.test(name || '');
  }
  document.addEventListener('click', function (e) {
    try {
      var a = e.target && e.target.closest ? e.target.closest('a') : null;
      if (!a || !a.href) return;
      var href = a.href;
      var name = a.getAttribute('download') || '';
      if (href.indexOf('mailto:') === 0 || href.indexOf('tel:') === 0) {
        e.preventDefault();
        e.stopPropagation();
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('bridgeOpenExternal', href);
        }
        return;
      }
      if (!(name || href.indexOf('blob:') === 0 || isArchive(href, name))) return;
      e.preventDefault();
      e.stopPropagation();
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('bridgeDownload', href, name);
      }
    } catch (err) {}
  }, true);
})();
''';

/// Hide page-level scrollbars inside the WebView (scrolling still works).
const String _hideScrollbarCssJs = r'''
(function () {
  if (window.__bridgeHideScrollbar) return;
  window.__bridgeHideScrollbar = true;
  var css = 'html,body{-ms-overflow-style:none;scrollbar-width:none;}' +
    'html::-webkit-scrollbar,body::-webkit-scrollbar,*::-webkit-scrollbar{display:none;width:0;height:0;}';
  var style = document.createElement('style');
  style.type = 'text/css';
  style.appendChild(document.createTextNode(css));
  (document.head || document.documentElement).appendChild(style);
})();
''';

/// Android WebView often fails `WebAssembly.instantiateStreaming`; fall back
/// to ArrayBuffer instantiation so checkout / funding pages can boot.
const String _wasmFallbackJs = r'''
(function () {
  if (window.__bridgeWasmFix) return;
  window.__bridgeWasmFix = true;
  if (typeof WebAssembly === 'undefined' || !WebAssembly.instantiateStreaming) return;
  var original = WebAssembly.instantiateStreaming.bind(WebAssembly);
  WebAssembly.instantiateStreaming = function (source, imports) {
    return Promise.resolve(source).then(function (response) {
      return original(response, imports).catch(function () {
        return Promise.resolve(source).then(function (res) {
          return (res && res.arrayBuffer) ? res.arrayBuffer() : res;
        }).then(function (buffer) {
          return WebAssembly.instantiate(buffer, imports);
        });
      });
    });
  };
})();
''';

/// Android Chrome WebView still applies `env(safe-area-inset-bottom)` inside the
/// page even when Flutter SafeArea already inset the WebView, which makes the
/// bottom tab bar taller than iOS. Force viewport-fit=contain (so env()≈0) and
/// strip remaining safe-area padding / spacer nodes on bottom bars.
const String _androidBottomNavHeightFixJs = r'''
(function () {
  if (window.__bridgeAndroidNavFixInstalled) {
    if (typeof window.__bridgeAndroidNavFixRun === 'function') {
      window.__bridgeAndroidNavFixRun();
    }
    return;
  }
  window.__bridgeAndroidNavFixInstalled = true;

  function forceViewportContain() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var metas = document.querySelectorAll('meta[name="viewport"]');
    if (!metas.length) {
      var m = document.createElement('meta');
      m.setAttribute('name', 'viewport');
      m.setAttribute(
        'content',
        'width=device-width, initial-scale=1, viewport-fit=contain'
      );
      head.appendChild(m);
      return;
    }
    for (var i = 0; i < metas.length; i++) {
      var meta = metas[i];
      var c = meta.getAttribute('content') || '';
      if (/viewport-fit\s*=\s*cover/i.test(c)) {
        meta.setAttribute(
          'content',
          c.replace(/viewport-fit\s*=\s*cover/gi, 'viewport-fit=contain')
        );
      } else if (!/viewport-fit/i.test(c)) {
        meta.setAttribute('content', c + ', viewport-fit=contain');
      }
    }
  }

  function ensureCss() {
    if (document.getElementById('bridge-android-nav-fix')) return;
    var style = document.createElement('style');
    style.id = 'bridge-android-nav-fix';
    style.textContent =
      'html, body { padding-bottom: 0 !important; margin-bottom: 0 !important; }' +
      ':root, html, body {' +
      '  --safe-area-inset-bottom: 0px !important;' +
      '  --sab: 0px !important;' +
      '  --android-safe-area-inset-bottom: 0px !important;' +
      '  --ion-safe-area-bottom: 0px !important;' +
      '}' +
      '.pb-safe, .pb-safe-or-2, .pb-safe-or-4, .safe-area-bottom, .safe-pb,' +
      '.safe-area-inset-bottom, .pb-safe-bottom, .h-safe, .h-safe-bottom,' +
      '.safe-bottom, .ios-safe-bottom, [class*="pb-safe"], [class*="safe-area"] {' +
      '  padding-bottom: 0 !important;' +
      '  margin-bottom: 0 !important;' +
      '}' +
      '.h-safe, .h-safe-bottom, .safe-area-spacer, [class*="h-safe"] {' +
      '  height: 0 !important; min-height: 0 !important; max-height: 0 !important;' +
      '  padding: 0 !important; margin: 0 !important; overflow: hidden !important;' +
      '}';
    (document.head || document.documentElement).appendChild(style);
  }

  function readSafeAreaBottom() {
    if (!document.body) return 0;
    var probe = document.createElement('div');
    probe.style.cssText =
      'position:absolute;visibility:hidden;pointer-events:none;' +
      'padding-bottom:env(safe-area-inset-bottom, 0px);';
    document.body.appendChild(probe);
    var sab = parseFloat(window.getComputedStyle(probe).paddingBottom) || 0;
    probe.remove();
    return sab;
  }

  function nearBottom(rect, vh) {
    return rect.bottom >= vh - 8 && rect.top < vh;
  }

  function clampBottomBars() {
    forceViewportContain();
    ensureCss();
    if (!document.body) return;

    var sab = readSafeAreaBottom();
    var vh = window.innerHeight || document.documentElement.clientHeight || 0;
    if (!vh) return;

    var nodes = document.body.querySelectorAll('*');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var rect = el.getBoundingClientRect();
      if (rect.height <= 0 || rect.width <= 0) continue;
      if (!nearBottom(rect, vh) || rect.height > 160) continue;

      var cs = window.getComputedStyle(el);
      var pb = parseFloat(cs.paddingBottom) || 0;
      var mb = parseFloat(cs.marginBottom) || 0;
      var bottom = parseFloat(cs.bottom);
      var pos = cs.position;

      // Flutter already reserved the system nav inset. Strip only extra
      // safe-area padding so the tab bar is not double-tall — never collapse
      // the bar's own height (that hid it behind the system nav).
      if (sab > 0 && pb >= sab - 1) {
        el.style.setProperty(
          'padding-bottom',
          Math.max(0, pb - sab) + 'px',
          'important'
        );
      } else if (pb > 24) {
        el.style.setProperty('padding-bottom', '0px', 'important');
      }
      if (mb > 4) {
        el.style.setProperty('margin-bottom', '0px', 'important');
      }

      if (
        (pos === 'fixed' || pos === 'sticky') &&
        isFinite(bottom) &&
        bottom > 2
      ) {
        el.style.setProperty('bottom', '0px', 'important');
      }
    }
  }

  var applying = false;
  var scheduled = null;

  function run() {
    if (applying) return;
    applying = true;
    try {
      clampBottomBars();
    } finally {
      applying = false;
    }
  }

  function scheduleRun() {
    if (applying || scheduled != null) return;
    scheduled = setTimeout(function () {
      scheduled = null;
      run();
    }, 32);
  }

  window.__bridgeAndroidNavFixRun = run;

  forceViewportContain();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      ensureCss();
      run();
    });
  } else {
    ensureCss();
    run();
  }
  setTimeout(run, 50);
  setTimeout(run, 300);
  setTimeout(run, 800);
  setTimeout(run, 1600);
  setTimeout(run, 3000);
  try {
    new MutationObserver(function () {
      scheduleRun();
    }).observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['style', 'class'],
    });
  } catch (e) {}
  try {
    window.addEventListener('resize', scheduleRun, { passive: true });
  } catch (e2) {}
})();
''';

/// Embeddable Bridge shell — token → `POST /launch` → InAppWebView (mobile module).
class BridgeSdk extends StatefulWidget {
  const BridgeSdk({
    super.key,
    required this.token,
    required this.refreshToken,
    required this.clientName,
    required this.returnUrl,
    required this.environment,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    this.onReady,
    this.onReturn,
    this.onError,
    this.onDownloadSaved,
    this.onDownloadError,
    this.controller,
  });

  /// Host access token (`tokens.access_token`) → launch body `token`.
  final String token;

  /// Host refresh token (`tokens.refresh_token`) → launch body `refreshToken`.
  final String refreshToken;

  /// Host client id → launch body `clientName`.
  final String clientName;

  /// Custom app scheme return URL (e.g. `myapp://sdk-return`), not http(s).
  final String returnUrl;

  /// [Environment.UAT] or [Environment.PROD].
  final Environment environment;

  /// Epoch seconds/ms — `tokens.access_expires_at`.
  final String accessTokenExpiresAt;

  /// Epoch seconds/ms — `tokens.refresh_expires_at`.
  final String refreshTokenExpiresAt;

  final VoidCallback? onReady;

  /// Fired when Bridge navigates to [returnUrl] (never loads — intercepted).
  final ValueChanged<BridgeReturn>? onReturn;

  final ValueChanged<SdkError>? onError;

  /// Fired after a document was saved (blob ZIP / PDF / etc.).
  final ValueChanged<String>? onDownloadSaved;

  /// Fired when a download fails.
  final ValueChanged<Object>? onDownloadError;

  final ValueNotifier<BridgeSdkController?>? controller;

  @override
  State<BridgeSdk> createState() => _BridgeSdkState();
}

class _BridgeSdkState extends State<BridgeSdk> implements BridgeSdkController {
  final LaunchService _launchService = LaunchService();
  final DownloadService _downloadService = DownloadService();

  InAppWebViewController? _mainController;
  InAppWebViewController? _popupController;
  String? _launchUrl;
  int? _popupWindowId;
  String? _overlayUrl;
  bool _showOverlay = false;
  bool _bootstrapping = true;
  bool _returnFired = false;
  bool _sessionEnded = false;
  bool _readyFired = false;
  int _webViewInstanceKey = 0;
  BridgeReturn? _lastReturn;

  /// Android edge-to-edge: `MediaQuery.padding.bottom` is often 0 while the
  /// system nav bar still occupies `viewPadding.bottom`. Track that inset so
  /// the WebView sits above the bar when present.
  double _androidNavBarInset = 0;

  bool get _hasAndroidNavBar => _androidNavBarInset > 0.5;

  UnmodifiableListView<UserScript> _userScripts({
    required bool stripAndroidWebSafeArea,
  }) {
    final scripts = <UserScript>[
      UserScript(
        source: _wasmFallbackJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: _blobCaptureJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: _downloadClickJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      UserScript(
        source: _hideScrollbarCssJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ];
    // Only neutralize in-page safe-area when Flutter already reserved the
    // nav-bar inset — otherwise the web tab bar would sit under the system UI.
    if (stripAndroidWebSafeArea) {
      scripts.add(
        UserScript(
          source: _androidBottomNavHeightFixJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      );
    }
    return UnmodifiableListView<UserScript>(scripts);
  }

  InAppWebViewSettings get _webSettings => InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsBackForwardNavigationGestures: true,
        useOnDownloadStart: true,
        // iOS: inspect response MIME so PDFs are downloaded, not opened in-WebView.
        useOnNavigationResponse: true,
        // Required for shouldOverrideUrlLoading (custom-scheme returnUrl).
        useShouldOverrideUrlLoading: true,
        thirdPartyCookiesEnabled: true,
        sharedCookiesEnabled: true,
        iframeAllow: 'camera; microphone; payment; geolocation',
        iframeAllowFullscreen: true,
        isInspectable: !kReleaseMode,
        // Hide native WebView scrollbars (content still scrolls).
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        // Android: hybrid composition is more reliable for nested checkout iframes.
        useHybridComposition: true,
        allowContentAccess: true,
        allowFileAccess: true,
        // Keep Android text scale consistent with iOS WebView sizing.
        textZoom: 100,
        // Flutter SafeArea already insets the WebView. Without NEVER, iOS WKWebView
        // still reports safe-area-inset-bottom and the web tab bar double-pads.
        contentInsetAdjustmentBehavior:
            ScrollViewContentInsetAdjustmentBehavior.NEVER,
        // Bank/funding pages reject the "; wv" WebView UA marker — set before load.
        userAgent: null,
      );

  @override
  void initState() {
    super.initState();
    widget.controller?.value = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  @override
  void didUpdateWidget(covariant BridgeSdk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.value = null;
      widget.controller?.value = this;
    }

    final authChanged = widget.token != oldWidget.token ||
        widget.refreshToken != oldWidget.refreshToken ||
        widget.clientName != oldWidget.clientName ||
        widget.returnUrl != oldWidget.returnUrl ||
        widget.environment != oldWidget.environment ||
        widget.accessTokenExpiresAt != oldWidget.accessTokenExpiresAt ||
        widget.refreshTokenExpiresAt != oldWidget.refreshTokenExpiresAt;

    if (authChanged) {
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    widget.controller?.value = null;
    _launchService.close();
    _downloadService.close();
    super.dispose();
  }

  SdkError? _validateProps() {
    final required = <String, String>{
      'token': widget.token,
      'refreshToken': widget.refreshToken,
      'clientName': widget.clientName,
      'returnUrl': widget.returnUrl,
      'accessTokenExpiresAt': widget.accessTokenExpiresAt,
      'refreshTokenExpiresAt': widget.refreshTokenExpiresAt,
    };
    for (final entry in required.entries) {
      if (entry.value.isEmpty) {
        return SdkError(
          SdkErrorCode.invalidConfig,
          'BridgeSDK: required prop "${entry.key}" must be a non-empty string',
        );
      }
    }
    final returnCheck = validateReturnUrl(widget.returnUrl);
    if (!returnCheck.ok) {
      return SdkError(
        SdkErrorCode.invalidConfig,
        'BridgeSDK: returnUrl rejected — ${returnCheck.reason}',
      );
    }
    return null;
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _bootstrapping = true;
      _mainController = null;
      _popupController = null;
      _launchUrl = null;
      _showOverlay = false;
      _popupWindowId = null;
      _overlayUrl = null;
      _returnFired = false;
      _sessionEnded = false;
      _lastReturn = null;
      _readyFired = false;
    });

    final configError = _validateProps();
    if (configError != null) {
      debugPrint(configError.message);
      widget.onError?.call(configError);
      if (mounted) setState(() => _bootstrapping = false);
      return;
    }

    try {
      final launchUrl = await _launchService.fetchLaunchUrl(
        environment: widget.environment,
        request: LaunchRequest(
          token: widget.token,
          refreshToken: widget.refreshToken,
          clientName: widget.clientName,
          returnUrl: widget.returnUrl,
          accessTokenExpiresAt: widget.accessTokenExpiresAt,
          refreshTokenExpiresAt: widget.refreshTokenExpiresAt,
        ),
      );

      final schemeCheck = validateHttpsUrl(launchUrl);
      if (!schemeCheck.ok) {
        final err = SdkError(
          SdkErrorCode.launchFailed,
          'BridgeSDK: launchUrl rejected — ${schemeCheck.reason}',
        );
        debugPrint(err.message);
        widget.onError?.call(err);
        if (mounted) setState(() => _bootstrapping = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _launchUrl = launchUrl;
        _webViewInstanceKey += 1;
        _bootstrapping = false;
      });
    } on SdkError catch (error) {
      debugPrint(error.message);
      widget.onError?.call(error);
      if (mounted) setState(() => _bootstrapping = false);
    } catch (error) {
      final err = SdkError(
        SdkErrorCode.launchFailed,
        'BridgeSDK: unexpected launch error — $error',
        error,
      );
      debugPrint(err.message);
      widget.onError?.call(err);
      if (mounted) setState(() => _bootstrapping = false);
    }
  }

  Future<void> _prepareController(InAppWebViewController controller) async {
    try {
      final ua = await controller.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      if (ua is String) {
        final cleaned =
            ua.replaceAll('; wv', '').replaceAll('"', '').trim();
        await controller.setSettings(
          settings: InAppWebViewSettings(
            userAgent: '$cleaned BridgeSDK/$_sdkVersion',
            // Re-assert after UA change — checkout iframes need this on Android.
            thirdPartyCookiesEnabled: true,
            javaScriptCanOpenWindowsAutomatically: true,
            supportMultipleWindows: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('BridgeSDK: prepare controller warning — $e');
    }
  }

  void _registerDownloadHandler(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'bridgeDownload',
      callback: (args) {
        final url = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
        final name = args.length > 1 ? args[1]?.toString() : null;
        if (url.isEmpty) return null;
        unawaited(
          _downloadService
              .saveFromWebView(
            controller: controller,
            url: url,
            suggestedName: (name == null || name.isEmpty) ? null : name,
          )
              .then((saved) {
            debugPrint('BridgeSDK: saved download $saved');
            widget.onDownloadSaved?.call(saved);
          }).catchError((Object e) {
            debugPrint('BridgeSDK: bridgeDownload failed — $e');
            widget.onDownloadError?.call(e);
          }),
        );
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'bridgeOpenExternal',
      callback: (args) {
        final raw = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
        if (raw.isEmpty) return null;
        final uri = Uri.tryParse(raw);
        if (uri == null) return null;
        if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
          unawaited(_openExternalApp(uri));
        }
        return null;
      },
    );
  }

  Future<void> _loadLaunchUrl(
    InAppWebViewController controller,
    String launchUrl,
  ) async {
    await _prepareController(controller);
    debugPrint('BridgeSDK: loading launchUrl=$launchUrl');
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(launchUrl)),
    );
  }

  /// Opens `mailto:` / `tel:` in the device's default mail / phone app.
  Future<void> _openExternalApp(Uri uri) async {
    final url = uri.toString();
    debugPrint('BridgeSDK: opening external app url=$url');
    try {
      final ok = await url_launcher.launchUrl(
        uri,
        mode: url_launcher.LaunchMode.externalApplication,
      );
      if (!ok) {
        // Fallback for hosts that reject externalApplication for mailto/tel.
        final fallback = await url_launcher.launchUrl(
          uri,
          mode: url_launcher.LaunchMode.platformDefault,
        );
        if (!fallback) {
          throw StateError('No app available to handle $url');
        }
      }
    } catch (e) {
      debugPrint('BridgeSDK: could not open $url — $e');
      widget.onError?.call(
        SdkError(SdkErrorCode.webviewLoadFailed, 'Could not open $url', e),
      );
    }
  }

  /// Decide whether a main-frame navigation should move into the overlay.
  ///
  /// Funding / checkout must stay in the normal WebView flow on Android.
  /// Android marks many in-page navigations as `hasGesture`, and intercepting
  /// those into a fresh overlay breaks the session. Real popups still go through
  /// [onCreateWindow] (`window.open` / `target=_blank`).
  ///
  /// Document links (PDF, etc.) may still open in the overlay for viewing.
  bool _shouldOpenInOverlay(NavigationAction action) {
    if (action.isRedirect == true) return false;

    // POST (and other non-GET) must stay in the current WebView — overlay
    // only supports a GET loadUrl and would drop the body.
    final method = action.request.method?.toUpperCase() ?? 'GET';
    if (method != 'GET') return false;

    final url = action.request.url?.toString() ?? '';
    final isDocumentLink = shouldSaveDocument(url: url);

    // Android: only peel document links into the overlay. Everything else
    // (including funding) continues in-place or via onCreateWindow.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (!isDocumentLink) return false;
      return action.navigationType == NavigationType.LINK_ACTIVATED ||
          action.hasGesture == true;
    }

    if (action.navigationType == NavigationType.LINK_ACTIVATED) return true;
    if (action.hasGesture == true) return true;

    // iOS/macOS: target=_blank has a null targetFrame.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        action.targetFrame == null &&
        action.isForMainFrame) {
      return true;
    }
    return false;
  }

  Future<NavigationActionPolicy> _handleNavigation(
    InAppWebViewController controller,
    NavigationAction navigationAction, {
    required bool fromOverlay,
  }) async {
    final uri = navigationAction.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;

    final url = uri.toString();
    final isMainFrame = navigationAction.isForMainFrame;

    // SPA / iframe bootstrap — never cancel.
    // Only treat main-frame blob/data as a download when it is clearly a file
    // (zip/pdf/…). Cancelling arbitrary data: URLs breaks Android module loads.
    if (isIgnorableNavigationScheme(url)) {
      final lower = url.toLowerCase();
      if (isMainFrame &&
          (lower.startsWith('blob:') || lower.startsWith('data:')) &&
          shouldForceDownload(url: url)) {
        unawaited(_saveUrl(controller, url, fromOverlay: fromOverlay));
        return NavigationActionPolicy.CANCEL;
      }
      return NavigationActionPolicy.ALLOW;
    }

    // Subframes (ads, DigiLocker iframes, etc.) must always proceed.
    if (!isMainFrame) {
      return NavigationActionPolicy.ALLOW;
    }

    if (isReturnUrl(url, widget.returnUrl)) {
      _fireReturn(url);
      return NavigationActionPolicy.CANCEL;
    }

    // mailto: / tel: — open the default system app (never the WebView).
    if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
      unawaited(_openExternalApp(uri));
      return NavigationActionPolicy.CANCEL;
    }

    // Explicit downloads only (download attr / zip). PDF/doc links open instead.
    if (navigationAction.shouldPerformDownload == true ||
        ((uri.scheme == 'http' || uri.scheme == 'https') &&
            shouldForceDownload(url: url))) {
      debugPrint('BridgeSDK: forcing download url=$url');
      unawaited(_saveUrl(controller, url, fromOverlay: fromOverlay));
      return NavigationActionPolicy.CANCEL;
    }

    if (isBlockedScheme(url)) {
      debugPrint('WebView navigation blocked (scheme): $url');
      return NavigationActionPolicy.CANCEL;
    }

    // User-tapped links (including PDFs) → closable overlay for viewing.
    if (!fromOverlay &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        _shouldOpenInOverlay(navigationAction)) {
      debugPrint('BridgeSDK: opening link in overlay url=$url');
      _openUrlOverlay(url);
      return NavigationActionPolicy.CANCEL;
    }

    // Allow redirects, programmatic loads, and in-overlay navigations.
    return NavigationActionPolicy.ALLOW;
  }

  Future<void> _saveUrl(
    InAppWebViewController controller,
    String url, {
    required bool fromOverlay,
    String? suggestedName,
  }) async {
    try {
      final name = await _downloadService.saveFromWebView(
        controller: controller,
        url: url,
        suggestedName: suggestedName,
      );
      debugPrint('BridgeSDK: saved download $name');
      widget.onDownloadSaved?.call(name);
      if (fromOverlay &&
          mounted &&
          _popupController != null &&
          !await _popupController!.canGoBack()) {
        // Overlay was opened only for a file — dismiss after save.
        _closeOverlay();
      }
    } catch (e) {
      debugPrint('BridgeSDK: download failed — $e');
      widget.onDownloadError?.call(e);
    }
  }

  Future<void> _onDownload(
    InAppWebViewController controller,
    DownloadStartRequest request, {
    bool fromOverlay = false,
  }) async {
    debugPrint(
      'BridgeSDK: onDownloadStart mime=${request.mimeType} '
      'file=${request.suggestedFilename} url=${request.url}',
    );
    await _downloadService.handleDownloadStart(
      controller: controller,
      request: request,
      onSaved: (name) {
        debugPrint('BridgeSDK: saved download $name');
        widget.onDownloadSaved?.call(name);
      },
      onError: (error) {
        widget.onDownloadError?.call(error);
      },
    );
    if (fromOverlay && mounted && !await controller.canGoBack()) {
      _closeOverlay();
    }
  }

  /// iOS (SDK_UAT): show MIME types WK can render (PDF); download the rest.
  /// Zip / bulk packages are always saved.
  Future<NavigationResponseAction?> _handleNavigationResponse(
    InAppWebViewController controller,
    NavigationResponse navigationResponse, {
    required bool fromOverlay,
  }) async {
    if (!navigationResponse.isForMainFrame) {
      return NavigationResponseAction.ALLOW;
    }

    final response = navigationResponse.response;
    final mime = response?.mimeType;
    final url = response?.url?.toString() ?? '';
    final suggested = response?.suggestedFilename;

    final forceSave = shouldForceDownload(
      url: url,
      mimeType: mime,
      suggestedFileName: suggested,
    );
    // Match native guide: canShowMIMEType ? allow : download.
    final cannotShow = !navigationResponse.canShowMIMEType;

    if (forceSave || cannotShow) {
      debugPrint(
        'BridgeSDK: navigationResponse → download mime=$mime '
        'file=$suggested url=$url canShow=${navigationResponse.canShowMIMEType}',
      );
      if (url.isNotEmpty) {
        unawaited(
          _saveUrl(
            controller,
            url,
            fromOverlay: fromOverlay,
            suggestedName: suggested,
          ),
        );
        return NavigationResponseAction.CANCEL;
      }
      return NavigationResponseAction.DOWNLOAD;
    }

    return NavigationResponseAction.ALLOW;
  }

  bool _maybeHandleReturn(String? url) {
    if (url == null || url.isEmpty) return false;
    if (!isReturnUrl(url, widget.returnUrl)) return false;
    _fireReturn(url);
    return true;
  }

  void _fireReturn(String url) {
    if (_returnFired) return;
    _returnFired = true;
    final result = BridgeReturn(url: url, reason: returnReason(url));
    _lastReturn = result;
    debugPrint(
      'BridgeSDK: intercepted returnUrl reason=${result.reason} url=$url',
    );
    unawaited(_mainController?.stopLoading());
    unawaited(_popupController?.stopLoading());
    _closeOverlay();
    if (mounted) {
      setState(() => _sessionEnded = true);
    }
    widget.onReturn?.call(result);
  }

  Future<PermissionResponse> _handlePermissionRequest(
    PermissionRequest request,
  ) async {
    final needsCamera = request.resources.contains(PermissionResourceType.CAMERA);
    final needsMic =
        request.resources.contains(PermissionResourceType.MICROPHONE);

    if (needsCamera && !(await Permission.camera.request()).isGranted) {
      return PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      );
    }
    if (needsMic && !(await Permission.microphone.request()).isGranted) {
      return PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      );
    }
    return PermissionResponse(
      resources: request.resources,
      action: PermissionResponseAction.GRANT,
    );
  }

  Future<bool?> _handleCreateWindow(CreateWindowAction createWindowAction) async {
    if (!mounted) return false;
    final url = createWindowAction.request.url?.toString();
    debugPrint(
      'BridgeSDK: createWindow id=${createWindowAction.windowId} url=$url',
    );

    if (url != null && url.isNotEmpty) {
      final parsed = Uri.tryParse(url);
      if (parsed != null &&
          (parsed.scheme == 'mailto' || parsed.scheme == 'tel')) {
        unawaited(_openExternalApp(parsed));
        return false;
      }
      // Zip / bulk download via window.open → save. PDFs open in overlay.
      if (!isIgnorableNavigationScheme(url) && shouldForceDownload(url: url)) {
        final controller = _mainController;
        if (controller != null) {
          unawaited(_saveUrl(controller, url, fromOverlay: false));
        }
        return false;
      }
    }

    setState(() {
      _showOverlay = true;
      _popupWindowId = createWindowAction.windowId;
      _overlayUrl = null;
    });
    // Android needs the windowId WebView mounted before we accept the popup.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;
    return true;
  }

  void _openUrlOverlay(String url) {
    if (!mounted) return;

    final parsed = Uri.tryParse(url);
    if (parsed != null &&
        (parsed.scheme == 'mailto' || parsed.scheme == 'tel')) {
      unawaited(_openExternalApp(parsed));
      return;
    }

    // Zip / bulk package → save. PDF/doc links open in the overlay viewer.
    if (shouldForceDownload(url: url)) {
      final controller = _mainController;
      if (controller != null) {
        unawaited(_saveUrl(controller, url, fromOverlay: false));
      }
      return;
    }

    setState(() {
      _showOverlay = true;
      _popupWindowId = null;
      _overlayUrl = url;
    });
  }

  void _closeOverlay() {
    if (!mounted) return;
    setState(() {
      _showOverlay = false;
      _popupWindowId = null;
      _overlayUrl = null;
      _popupController = null;
    });
  }

  Future<void> _handleBack() async {
    if (_showOverlay) {
      if (_popupController != null && await _popupController!.canGoBack()) {
        await _popupController!.goBack();
      } else {
        _closeOverlay();
      }
      return;
    }
    if (_mainController != null && await _mainController!.canGoBack()) {
      await _mainController!.goBack();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Future<void> reload() => _bootstrap();

  Widget _buildSessionEnded() {
    final reason = _lastReturn?.reason;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              reason == null
                  ? 'Bridge session ended'
                  : 'Bridge returned: $reason',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Host app should handle onReturn (close this screen / continue).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainWebView(String launchUrl) {
    final stripAndroidWebSafeArea = _hasAndroidNavBar;
    return InAppWebView(
      key: ValueKey('main-$_webViewInstanceKey'),
      initialSettings: _webSettings,
      initialUserScripts: _userScripts(
        stripAndroidWebSafeArea: stripAndroidWebSafeArea,
      ),
      onWebViewCreated: (controller) async {
        _mainController = controller;
        _registerDownloadHandler(controller);
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          await InAppWebViewController.setWebContentsDebuggingEnabled(
            !kReleaseMode,
          );
        }
        await _loadLaunchUrl(controller, launchUrl);
      },
      shouldOverrideUrlLoading: (controller, action) =>
          _handleNavigation(controller, action, fromOverlay: false),
      onLoadStart: (controller, url) {
        final s = url?.toString();
        if (s != null && isReturnUrl(s, widget.returnUrl)) {
          _maybeHandleReturn(s);
        }
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        final s = url?.toString();
        if (s != null && isReturnUrl(s, widget.returnUrl)) {
          _maybeHandleReturn(s);
        }
      },
      onPermissionRequest: (controller, request) =>
          _handlePermissionRequest(request),
      onCreateWindow: (controller, action) => _handleCreateWindow(action),
      onCloseWindow: (controller) {},
      onLoadStop: (controller, url) async {
        final s = url?.toString();
        if (s != null && _maybeHandleReturn(s)) return;
        // Re-inject click interceptor for SPAs that replace the document.
        try {
          await controller.evaluateJavascript(source: _downloadClickJs);
          await controller.evaluateJavascript(source: _hideScrollbarCssJs);
          if (stripAndroidWebSafeArea) {
            await controller.evaluateJavascript(
              source: _androidBottomNavHeightFixJs,
            );
          }
        } catch (_) {}
        if (!_readyFired) {
          _readyFired = true;
          debugPrint('BridgeSDK: page ready url=$s');
          widget.onReady?.call();
        }
      },
      onReceivedError: (controller, request, error) {
        final failing = request.url.toString();
        if (isReturnUrl(failing, widget.returnUrl)) {
          _maybeHandleReturn(failing);
          return;
        }
        if (isIgnorableNavigationScheme(failing)) return;
        if (error.type == WebResourceErrorType.CANCELLED) return;
        final desc = error.description.toLowerCase();
        if (desc.contains('cancelled') ||
            desc.contains('canceled') ||
            desc.contains('error -999')) {
          return;
        }
        if (request.isForMainFrame ?? true) {
          debugPrint(
            'BridgeSDK: load error ${error.type} ${error.description} url=$failing',
          );
          widget.onError?.call(
            SdkError(
              SdkErrorCode.webviewLoadFailed,
              error.description,
              error,
            ),
          );
        }
      },
      onDownloadStartRequest: (controller, request) =>
          _onDownload(controller, request),
      onNavigationResponse: (controller, response) =>
          _handleNavigationResponse(
            controller,
            response,
            fromOverlay: false,
          ),
    );
  }

  Widget _buildOverlayWebView() {
    final windowId = _popupWindowId;
    final overlayUrl = _overlayUrl;
    final stripAndroidWebSafeArea = _hasAndroidNavBar;

    return InAppWebView(
      key: ValueKey(
        windowId != null ? 'popup-$windowId' : 'overlay-$overlayUrl',
      ),
      windowId: windowId,
      initialSettings: _webSettings,
      initialUserScripts: _userScripts(
        stripAndroidWebSafeArea: stripAndroidWebSafeArea,
      ),
      onWebViewCreated: (controller) async {
        _popupController = controller;
        _registerDownloadHandler(controller);
        await _prepareController(controller);
        if (windowId == null && overlayUrl != null) {
          if (shouldForceDownload(url: overlayUrl)) {
            await _saveUrl(controller, overlayUrl, fromOverlay: true);
            return;
          }
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(overlayUrl)),
          );
        }
      },
      shouldOverrideUrlLoading: (controller, action) =>
          _handleNavigation(controller, action, fromOverlay: true),
      onLoadStart: (controller, url) {
        final s = url?.toString();
        if (s != null && isReturnUrl(s, widget.returnUrl)) {
          _maybeHandleReturn(s);
        }
      },
      onLoadStop: (controller, url) async {
        try {
          await controller.evaluateJavascript(source: _downloadClickJs);
          await controller.evaluateJavascript(source: _hideScrollbarCssJs);
        } catch (_) {}
      },
      onPermissionRequest: (controller, request) =>
          _handlePermissionRequest(request),
      onCloseWindow: (controller) => _closeOverlay(),
      onReceivedError: (controller, request, error) {
        final failing = request.url.toString();
        if (isReturnUrl(failing, widget.returnUrl)) {
          _maybeHandleReturn(failing);
        }
      },
      onDownloadStartRequest: (controller, request) =>
          _onDownload(controller, request, fromOverlay: true),
      onNavigationResponse: (controller, response) =>
          _handleNavigationResponse(
            controller,
            response,
            fromOverlay: true,
          ),
    );
  }

  Widget _buildOverlay() {
    // Funding / checkout popups (`window.open` → onCreateWindow) must be
    // full-bleed with no host close chrome. Document overlays keep the bar.
    final isFundingPopup = _popupWindowId != null;

    return Positioned.fill(
      child: Material(
        color: Colors.white,
        elevation: 8,
        child: Column(
          children: [
            if (!isFundingPopup)
              Material(
                color: const Color(0xFFF5F5F5),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Close to return',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: _closeOverlay,
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildOverlayWebView()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    // Edge-to-edge Android zeros MediaQuery.padding; nav bar lives in viewPadding.
    final androidNavBarInset =
        isAndroid ? MediaQuery.viewPaddingOf(context).bottom : 0.0;
    _androidNavBarInset = androidNavBarInset;
    final hasAndroidNavBar = androidNavBarInset > 0.5;

    // Hybrid InAppWebView often ignores Padding and paints under the system
    // nav bar. A sibling SizedBox below an Expanded WebView constrains it.
    final Widget shell = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: _bootstrapping || _launchUrl == null
          ? const Center(child: CircularProgressIndicator())
          : _sessionEnded
              ? _buildSessionEnded()
              : Stack(
                  children: [
                    Positioned.fill(
                      child: _buildMainWebView(_launchUrl!),
                    ),
                    if (_showOverlay &&
                        (_popupWindowId != null || _overlayUrl != null))
                      _buildOverlay(),
                  ],
                ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: Colors.white,
        // iOS: SafeArea + contentInsetAdjustmentBehavior.NEVER (no double pad).
        // Android: reserve viewPadding.bottom with a real layout sibling when
        // a system navigation / back-handler bar is present.
        child: SafeArea(
          top: true,
          bottom: !isAndroid,
          left: false,
          right: false,
          child: hasAndroidNavBar
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ClipRect stops hybrid WebView from painting under the nav bar.
                    Expanded(child: ClipRect(child: shell)),
                    SizedBox(height: androidNavBarInset),
                  ],
                )
              : shell,
        ),
      ),
    );
  }
}
