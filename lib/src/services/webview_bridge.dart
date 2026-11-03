import '../internal/constants.dart';
import '../internal/security.dart';
import '../types/types.dart';

/// Builds JS snippets injected into the WebView.
///
/// Keeps the React Native web contract:
/// - `window.__RN_WEBVIEW_CONFIG__`
/// - `window.ReactNativeWebView.postMessage`
class WebViewBridge {
  const WebViewBridge();

  /// Channel name registered with [WebViewController.addJavaScriptChannel].
  static const String flutterChannelName = 'FlutterBridge';

  /// Shim so the existing web app can keep calling ReactNativeWebView.postMessage.
  String getBridgeShimScript() {
    return '''
      (function() {
        try {
          if (!window.ReactNativeWebView) {
            window.ReactNativeWebView = {
              postMessage: function(data) {
                try {
                  var payload = (typeof data === 'string') ? data : JSON.stringify(data);
                  $flutterChannelName.postMessage(payload);
                } catch (e) {}
              }
            };
          }
        } catch (e) {}
        true;
      })();
    ''';
  }

  String getInjectionScript(
    AuthTokens tokens,
    WebViewInjectedConfig config, {
    bool enableApiLogs = false,
  }) {
    final merged = <String, dynamic>{
      ...tokens,
      ...config.toJson(),
    };
    return '''
      (function() {
        try {
          if (!window.ReactNativeWebView) {
            window.ReactNativeWebView = {
              postMessage: function(data) {
                try {
                  var payload = (typeof data === 'string') ? data : JSON.stringify(data);
                  $flutterChannelName.postMessage(payload);
                } catch (e) {}
              }
            };
          }
          window.__RN_WEBVIEW_CONFIG__ = Object.assign(
            {},
            ${safeJsLiteral(merged)}
          );
          ${enableApiLogs ? _networkLoggingScript : ''}
          if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
            window.ReactNativeWebView.postMessage(JSON.stringify({
              type: 'test.injected',
              payload: { ok: true, stage: 'before-content-loaded' }
            }));
          }
        } catch (e) {}
        true;
      })();
    ''';
  }

  /// Intercepts fetch + XHR and posts compact request/response logs to Flutter.
  static const String _networkLoggingScript = r'''
          (function() {
            var __bridgePost = function(type, payload) {
              try {
                if (window.ReactNativeWebView && window.ReactNativeWebView.postMessage) {
                  window.ReactNativeWebView.postMessage(JSON.stringify({
                    type: type,
                    payload: payload
                  }));
                }
              } catch (e) {}
            };
            var __truncate = function(value, max) {
              try {
                var text = (typeof value === 'string') ? value : JSON.stringify(value);
                if (!text) return text;
                return text.length > max ? text.slice(0, max) + '…' : text;
              } catch (e) {
                return '[unserializable]';
              }
            };
            if (!window.fetch.__bridgeWrapped) {
              var __origFetch = window.fetch.bind(window);
              var wrappedFetch = function(input, init) {
                var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
                var url = (typeof input === 'string')
                  ? input
                  : (input && input.url) ? input.url : String(input);
                var started = Date.now();
                __bridgePost('debug.network', {
                  phase: 'request',
                  transport: 'fetch',
                  method: method,
                  url: url,
                  body: init && init.body ? __truncate(init.body, 500) : null
                });
                return __origFetch(input, init).then(function(response) {
                  var clone = response.clone();
                  clone.text().then(function(text) {
                    __bridgePost('debug.network', {
                      phase: 'response',
                      transport: 'fetch',
                      method: method,
                      url: url,
                      status: response.status,
                      durationMs: Date.now() - started,
                      body: __truncate(text, 800)
                    });
                  }).catch(function() {
                    __bridgePost('debug.network', {
                      phase: 'response',
                      transport: 'fetch',
                      method: method,
                      url: url,
                      status: response.status,
                      durationMs: Date.now() - started,
                      body: '[body unavailable]'
                    });
                  });
                  return response;
                }).catch(function(error) {
                  __bridgePost('debug.network', {
                    phase: 'error',
                    transport: 'fetch',
                    method: method,
                    url: url,
                    durationMs: Date.now() - started,
                    error: String(error)
                  });
                  throw error;
                });
              };
              wrappedFetch.__bridgeWrapped = true;
              window.fetch = wrappedFetch;
            }
            if (!XMLHttpRequest.prototype.__bridgeWrapped) {
              var __origOpen = XMLHttpRequest.prototype.open;
              var __origSend = XMLHttpRequest.prototype.send;
              XMLHttpRequest.prototype.open = function(method, url) {
                this.__bridgeMethod = method;
                this.__bridgeUrl = url;
                return __origOpen.apply(this, arguments);
              };
              XMLHttpRequest.prototype.send = function(body) {
                var xhr = this;
                var started = Date.now();
                __bridgePost('debug.network', {
                  phase: 'request',
                  transport: 'xhr',
                  method: (xhr.__bridgeMethod || 'GET').toUpperCase(),
                  url: String(xhr.__bridgeUrl || ''),
                  body: body ? __truncate(body, 500) : null
                });
                xhr.addEventListener('loadend', function() {
                  __bridgePost('debug.network', {
                    phase: 'response',
                    transport: 'xhr',
                    method: (xhr.__bridgeMethod || 'GET').toUpperCase(),
                    url: String(xhr.__bridgeUrl || ''),
                    status: xhr.status,
                    durationMs: Date.now() - started,
                    body: __truncate(xhr.responseText, 800)
                  });
                });
                return __origSend.apply(this, arguments);
              };
              XMLHttpRequest.prototype.__bridgeWrapped = true;
            }
            if (!window.__BRIDGE_PERF_LOGS__ && window.PerformanceObserver) {
              window.__BRIDGE_PERF_LOGS__ = true;
              try {
                var observer = new PerformanceObserver(function(list) {
                  list.getEntries().forEach(function(entry) {
                    if (!entry || !entry.name) return;
                    var initiator = entry.initiatorType || '';
                    if (initiator !== 'fetch' && initiator !== 'xmlhttprequest' && initiator !== 'other') {
                      return;
                    }
                    __bridgePost('debug.network', {
                      phase: 'response',
                      transport: 'perf:' + initiator,
                      method: 'GET',
                      url: entry.name,
                      status: 0,
                      durationMs: Math.round(entry.duration || 0),
                      body: null
                    });
                  });
                });
                observer.observe({ entryTypes: ['resource'] });
              } catch (e) {}
            }
            if (!window.__BRIDGE_API_LOGS_PING__) {
              window.__BRIDGE_API_LOGS_PING__ = true;
              __bridgePost('debug.network', {
                phase: 'request',
                transport: 'logger',
                method: 'INIT',
                url: 'bridge-api-logs-enabled',
                body: null
              });
              try {
                var existing = performance.getEntriesByType('resource') || [];
                existing.forEach(function(entry) {
                  if (!entry || !entry.name) return;
                  var initiator = entry.initiatorType || '';
                  if (initiator !== 'fetch' && initiator !== 'xmlhttprequest') return;
                  __bridgePost('debug.network', {
                    phase: 'response',
                    transport: 'perf:' + initiator,
                    method: 'GET',
                    url: entry.name,
                    status: 0,
                    durationMs: Math.round(entry.duration || 0),
                    body: null
                  });
                });
              } catch (e) {}
              // Smoke-test that fetch wrapping works.
              try {
                window.fetch('https://trade-internal-staging.viewtrade.in/', {
                  method: 'HEAD',
                  cache: 'no-store'
                }).catch(function() {});
              } catch (e) {}
            }
          })();
  ''';

  String getClearAuthScript() {
    return '''
      (function() {
        try {
          var authKeys = ${safeJsLiteral(webviewAuthKeys)};
          var nextConfig = Object.assign({}, window.__RN_WEBVIEW_CONFIG__ || {});
          authKeys.forEach(function(key) {
            try { delete nextConfig[key]; } catch (e) {}
            try { window.localStorage && window.localStorage.removeItem(key); } catch (e) {}
            try { window.sessionStorage && window.sessionStorage.removeItem(key); } catch (e) {}
          });
          nextConfig.isAuthenticated = false;
          window.__RN_WEBVIEW_CONFIG__ = nextConfig;
          window.dispatchEvent(new CustomEvent('rn-config', {
            detail: Object.assign({}, nextConfig, { type: 'logout' })
          }));
        } catch (e) {}
        true;
      })();
    ''';
  }

  String getLocationScript(String url) {
    return '''
      (function() {
        try { window.location.replace(${safeJsLiteral(url)}); } catch (e) {}
        true;
      })();
    ''';
  }

  String getPostMessageScript(Object? message) {
    return '''
      (function() {
        try {
          window.dispatchEvent(new MessageEvent('message', {
            data: ${safeJsLiteral(message)}
          }));
        } catch (e) {}
        true;
      })();
    ''';
  }
}

const webViewBridge = WebViewBridge();
