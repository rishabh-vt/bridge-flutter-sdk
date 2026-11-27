const List<String> blockedSchemes = [
  'javascript:',
  'file:',
  'intent:',
  'content:',
  'view-source:',
];

/// Schemes that WebViews use during bootstrap / iframes — never cancel these.
bool isIgnorableNavigationScheme(String url) {
  final lower = url.trim().toLowerCase();
  return lower.startsWith('about:') ||
      lower.startsWith('data:') ||
      lower.startsWith('blob:');
}

bool isBlockedScheme(String url) {
  final lower = url.trim().toLowerCase();
  return blockedSchemes.any(lower.startsWith);
}

/// Launch URLs from Bridge must be HTTPS.
({bool ok, String? reason}) validateHttpsUrl(String url) {
  late final Uri parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return (ok: false, reason: 'malformed URL');
  }
  if (parsed.scheme == 'https') return (ok: true, reason: null);
  return (
    ok: false,
    reason: 'non-HTTPS URL not permitted (got ${parsed.scheme}:)',
  );
}

/// Host-supplied [returnUrl] is dynamic: custom app scheme
/// (`myapp://sdk-return`) or any HTTPS URL. Plain `http` is rejected.
({bool ok, String? reason}) validateReturnUrl(String url) {
  late final Uri parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return (ok: false, reason: 'malformed URL');
  }
  final scheme = parsed.scheme.toLowerCase();
  if (scheme.isEmpty) {
    return (ok: false, reason: 'missing URL scheme');
  }
  if (scheme == 'http') {
    return (
      ok: false,
      reason:
          'returnUrl must be https or a custom app scheme (e.g. myapp://sdk-return), not http',
    );
  }
  if (scheme == 'https') {
    if (parsed.host.isEmpty) {
      return (ok: false, reason: 'https returnUrl requires a host');
    }
    return (ok: true, reason: null);
  }
  if (scheme == 'javascript' ||
      scheme == 'file' ||
      scheme == 'data' ||
      scheme == 'blob') {
    return (ok: false, reason: 'blocked scheme "$scheme"');
  }
  return (ok: true, reason: null);
}

String _stripQueryAndFragment(String url) {
  final noHash = url.split('#').first;
  return noHash.split('?').first;
}

String _cleanPath(String path) {
  if (path.isEmpty || path == '/') return '/';
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// True when [url] matches configured [returnUrl] (query / fragment ignored).
bool isReturnUrl(String url, String returnUrl) {
  if (returnUrl.isEmpty) return false;
  final normalized = url.trim();
  final target = returnUrl.trim();
  if (normalized.isEmpty) return false;

  final actualBase = _stripQueryAndFragment(normalized);
  final targetBase = _stripQueryAndFragment(target);

  if (actualBase.toLowerCase() == targetBase.toLowerCase()) return true;
  if (actualBase.toLowerCase().startsWith('${targetBase.toLowerCase()}/')) {
    return true;
  }

  try {
    final actual = Uri.parse(normalized);
    final expected = Uri.parse(target);
    if (actual.scheme.toLowerCase() != expected.scheme.toLowerCase()) {
      return false;
    }

    final isHttps = expected.scheme.toLowerCase() == 'https';
    if (isHttps) {
      if (actual.host.toLowerCase() != expected.host.toLowerCase()) {
        return false;
      }
      final ep = _cleanPath(expected.path);
      final ap = _cleanPath(actual.path);
      return ap == ep || (ep != '/' && ap.startsWith('$ep/'));
    }

    // myapp://sdk-return  → host = sdk-return
    if (expected.host.isNotEmpty) {
      return actual.host.toLowerCase() == expected.host.toLowerCase();
    }

    // myapp:///sdk-return or path-only forms
    String clean(String p) => p.replaceFirst(RegExp(r'^/+'), '');
    final ep = clean(expected.path);
    final ap = clean(actual.path);
    if (ep.isEmpty) return true;
    return ap == ep || ap.startsWith('$ep/');
  } catch (_) {
    return normalized.toLowerCase().startsWith(targetBase.toLowerCase());
  }
}

String? returnReason(String url) {
  try {
    return Uri.parse(url).queryParameters['reason'];
  } catch (_) {
    return null;
  }
}
